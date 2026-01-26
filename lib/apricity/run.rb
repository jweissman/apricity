# frozen_string_literal: true

require_relative "run/timestamps"
require_relative "run/node_state"
require_relative "run/step_state"
require_relative "run/state"
require_relative "run/result"
require_relative "run/subscriber"
require_relative "run/subscriptions"
require_relative "run_store"

module Apricity
  module Run
    # Event storage for runs
    class EventStore
      # In memory backend implementation
      class InMemoryBackend
        def initialize = @events = Hash.new { |h, k| h[k] = [] }
        def get_events(run_id) = @events[run_id]

        def get_events_json(run_id)
          @events[run_id].map { |e| Apricity::JobExecution::EventSerializer.as_json(e) }
        end

        def append_event(run_id, event)
          @events[run_id] << event
          Subscriptions.dispatch(run_id, event)
        end
      end

      # Redis backend implementation
      class RedisBackend
        RUN_TTL_SECONDS = 7 * 24 * 60 * 60 # 7 days
        MAX_TAIL = 32 * 1024 # 32 KB

        def initialize(redis:)
          @redis = redis
        end

        def get_events_json(run_id)
          redis.lrange(key(run_id), 0, -1)
        end

        def append_tail(run_id, event)
          stream = event.type == :stdout_chunk ? "stdout" : "stderr"
          k = "apricity:step_#{stream}:#{run_id}:#{event.node.id}:#{event.step.name}"

          redis.append(k, event.chunk)
          redis.expire(k, RUN_TTL_SECONDS)
          size = redis.strlen(k)
          return unless size > MAX_TAIL

          # trimmed = redis.getrange(k, size - MAX_TAIL, size)
          trimmed = redis.getrange(k, size - MAX_TAIL, size - 1)
          redis.set(k, trimmed, ex: RUN_TTL_SECONDS)
        end

        def append_event(run_id, event)
          event_json = Apricity::JobExecution::EventSerializer.as_json(event)
          if %i[stdout_chunk stderr_chunk].include?(event.type)
            Subscriptions.dispatch_json(run_id, event_json)
            append_tail(run_id, event)
            return
          end

          redis.rpush(key(run_id), event_json) # Apricity::JobExecution::EventSerializer.as_json(event))
          redis.expire(key(run_id), RUN_TTL_SECONDS)

          # Subscriptions.dispatch(run_id, event)
          Subscriptions.dispatch_json(run_id, event_json)
        end

        # { node_id => { step_name => { stdout, stderr }}}
        def output_tails(run_id)
          patterns = [
            "apricity:step_stdout:#{run_id}:*",
            "apricity:step_stderr:#{run_id}:*"
          ]
          tails = {}
          patterns.each do |pattern|
            # this is not super efficient but ok for now
            redis.scan_each(match: pattern) do |k|
              _prefix, step_stream, _run_id_again, node_id, step_name = k.split(":", 5)
              stream = step_stream.sub("step_", "") # => "stdout" / "stderr"
              tails[node_id] ||= {}
              tails[node_id][step_name] ||= {}
              chunk = redis.getrange(k, -MAX_TAIL, -1)
              tails[node_id][step_name][stream.to_sym] = chunk
            end
          end
          tails
        end

        private

        attr_reader :redis

        def key(run_id) = "apricity:events:#{run_id}"
      end

      include Singleton

      def initialize(
        backend: RedisBackend.new(redis: Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379")))
        # InMemoryBackend.new
      )
        @backend = backend
      end

      # def get_events(run_id) = backend.get_events(run_id)
      def get_events_json(run_id) = backend.get_events_json(run_id)

      def append_event(run_id, event)
        backend.append_event(run_id, event)
        RunStore.instance.apply_event(run_id:, event:)
      end

      # def self.get_events(run_id) = instance.get_events(run_id)
      def self.get_events_json(run_id) = instance.get_events_json(run_id)
      def self.append_event(run_id, event) = instance.append_event(run_id, event)

      private

      attr_reader :backend
    end

    Instance = Data.define(:id, :pipeline, :git_sha, :start_time) do
      def self.create(pipeline, git_sha: nil) = new(id: SecureRandom.uuid, pipeline:, git_sha:, start_time: Time.now)

      def started_at = run_record.created_at

      def finished? = status != :running

      def status
        case run_record&.status
        when "pending", "running"
          :running
        when "success"
          :success
        when "failure"
          :failure
        else
          :unknown
        end
      end

      def perform(&)
        # puts "!!! Run #{id} starting for pipeline '#{pipeline.slug}'"
        t0 = Time.now
        events = []
        step_states = runner.run do |event|
          # puts "* Run #{id} event: #{event.pretty}"
          events << event
          yield(event) if block_given?
          EventStore.append_event(id, event)
        end
        final_run_state = events.reduce(State.empty(pipeline)) { |state, event| state.reduce(event) }
        t1 = Time.now
        Result[run: self, step_states:, final_run_state:, started_at: t0, finished_at: t1]
      end

      private

      def run_record = Apricity::RunStore::RunRecord.get_run(id)

      def runner = Apricity::Pipeline::Runner.new(pipeline:, run_instance: self)
    end

    # lib/apricity/run_queue.rb
    class RunQueue
      include Singleton

      def push(run_id:, pipeline_slug:)
        redis.lpush("apricity:run_queue", JSON.dump({ run_id:, pipeline_slug: }))
      end

      def pop(blocking: true)
        _, payload = redis.brpop("apricity:run_queue", timeout: blocking ? 0 : 1)
        JSON.parse(payload, symbolize_names: true)
      end

      private

      def redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    end

    # Run performance worker (for background job exec)
    class Performer
      def self.enqueue(pipeline)
        run_id = SecureRandom.uuid

        # store minimal run metadata (web needs it)
        RunStore.instance.add_run_record(
          run_record_for(run_id:, pipeline:)
        )

        # enqueue job for a worker process to pick up
        RunQueue.instance.push(run_id:, pipeline_slug: pipeline.slug)

        run_id
      end

      def self.run_record_for(run_id:, pipeline:)
        RunStore::RunRecord.new(
          id: run_id,
          git_sha: "unknown",
          pipeline_slug: pipeline.slug,
          pipeline_name: pipeline.name,
          created_at: Time.now,
          status: "pending",
          cursor: nil
        )
      end

      def self.inline(pipeline)
        run = Run::Instance.create(pipeline)
        RunStore.instance.add_run(run)

        puts "Starting run #{run.id} for pipeline '#{pipeline.slug}'"
        Thread.new { run.perform }
        puts "Thread started for run #{run.id} for pipeline '#{pipeline.slug}'"

        run.id
      end

      def self.pipeline(pipeline)
        return inline(pipeline) if inline_run?

        enqueue(pipeline)
      end

      def self.inline_run? = ENV.fetch("APRICITY_INLINE_RUN", "false") == "true"
    end
  end
end
