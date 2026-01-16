# frozen_string_literal: true

require_relative "run/timestamps"
require_relative "run/node_state"
require_relative "run/step_state"
require_relative "run/state"
require_relative "run_store"

module Apricity
  module Run
    Result = Data.define(:run, :started_at, :finished_at, :step_states, :final_run_state) do
      def duration_seconds = (finished_at - started_at).round(2)
      def failed_nodes = final_run_state.nodes.values.select { it.status == :failure }
      def retryable? = failed_nodes.any?
      def passed? = failed_nodes.empty?
    end

    Subscriber = Data.define(:queue) do
      def push(event) = queue << event
    end

    # Manage subscribers for run events
    class Subscriptions
      # In memory backend implementation
      class InMemoryBackend
        def initialize = @subscribers = Hash.new { |h, k| h[k] = [] }
        def add_subscriber(run_id, subscriber) = @subscribers[run_id] << subscriber
        def remove_subscriber(run_id, subscriber) = @subscribers[run_id].delete(subscriber)

        def dispatch(run_id, event)
          subs = @subscribers[run_id].dup
          subs.each { |subscriber| subscriber.push(event) }
        end

        # def dispatch(run_id, event)
        #   @subscribers[run_id].each do |subscriber|
        #     subscriber.push(event)
        #   end
        # end
      end

      # Redis backend implementation
      class RedisBackend
        def initialize(redis_url:)
          @redis_url = redis_url
          @in_memory = InMemoryBackend.new
          @mutex = Mutex.new
          @started = false

          @threads = {} # [run_id, subscriber.object_id] => Thread
        end

        def ensure_started!
          return if @started

          @started = true

          Thread.new { pattern_subscribe("apricity:events_live:*") }
                .tap do |t|
            t.name = "apricity-redis-psub"
            t.abort_on_exception = true
            t.report_on_exception = true
          end
        end

        def pattern_subscribe(pattern)
          redis = Redis.new(url: redis_url)

          redis.psubscribe(pattern) do |on|
            on.pmessage do |_pattern, channel, msg|
              run_id = channel.split(":").last

              # @mutex.synchronize do
              @in_memory.dispatch(run_id, msg)
              # end
            end
          end
        end

        def add_subscriber(run_id, subscriber)
          ensure_started!
          @mutex.synchronize { @in_memory.add_subscriber(run_id, subscriber) }
        end

        def remove_subscriber(run_id, subscriber)
          @mutex.synchronize { @in_memory.remove_subscriber(run_id, subscriber) }
        end

        # def add_subscriber(run_id, subscriber)
        #   t = Thread.new do
        #     Redis.new(url: redis_url).subscribe(channel(run_id)) do |on|
        #       on.message do |_chan, msg|
        #         # event = Apricity::JobExecution::EventSerializer.from_json(msg)
        #         subscriber.push(msg) # event)
        #       end
        #     end
        #   end
        #   @threads[[run_id, subscriber.object_id]] = t
        # end

        # def remove_subscriber(run_id, subscriber)
        #   t = @threads.delete([run_id, subscriber.object_id])
        #   t&.kill
        # end

        def dispatch(run_id, event)
          Redis.new(url: redis_url).publish(channel(run_id), Apricity::JobExecution::EventSerializer.as_json(event))
        end

        private

        attr_reader :redis_url

        def channel(run_id) = "apricity:events_live:#{run_id}"
      end

      include Singleton

      def initialize(backend: RedisBackend.new(
        redis_url: ENV.fetch("REDIS_URL", "redis://localhost:6379")
      ))
        # InMemoryBackend.new)
        @backend = backend
      end

      def add_subscriber(run_id, subscriber) = backend.add_subscriber(run_id, subscriber)
      def remove_subscriber(run_id, subscriber) = backend.remove_subscriber(run_id, subscriber)
      def dispatch(run_id, event) = backend.dispatch(run_id, event)

      def self.add_subscriber(run_id, subscriber) = instance.add_subscriber(run_id, subscriber)
      def self.remove_subscriber(run_id, subscriber) = instance.remove_subscriber(run_id, subscriber)
      def self.dispatch(run_id, event) = instance.dispatch(run_id, event)

      private

      attr_reader :backend
    end

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
        def initialize(redis:)
          @redis = redis
        end

        # def get_events(run_id)
        #   redis.lrange(key(run_id), 0, -1).map do |json|
        #     Apricity::JobExecution::EventSerializer.from_json(json)
        #   end
        # end

        def get_events_json(run_id)
          redis.lrange(key(run_id), 0, -1)
        end

        def append_event(run_id, event)
          redis.rpush(key(run_id), Apricity::JobExecution::EventSerializer.as_json(event))
          Subscriptions.dispatch(run_id, event)
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

      # @events = Hash.new { |h, k| h[k] = [] }
      # def self.get_events(run_id) = @events[run_id]

      # def self.append_event(run_id, event)
      #   # $stdout.puts "[EventStore#append] #{event.type}: #{event.pretty}"
      #   @events[run_id] << event
      #   Subscriptions.dispatch(run_id, event)
      # end
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
        t0 = Time.now
        events = []
        step_states = runner.run do |event|
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
    class Worker
      def self.enqueue(pipeline)
        run_id = SecureRandom.uuid

        # store minimal run metadata (web needs it)
        RunStore.instance.add_run_record(
          RunStore::RunRecord.new(
            id: run_id,
            git_sha: "unknown",
            pipeline_slug: pipeline.slug,
            pipeline_name: pipeline.name,
            created_at: Time.now,
            status: "pending"
          )
        )

        # enqueue job for a worker process to pick up
        RunQueue.instance.push(run_id:, pipeline_slug: pipeline.slug)

        run_id
      end

      def self.perform(pipeline)
        run = Run::Instance.create(pipeline)
        RunStore.instance.add_run(run)

        Thread.new { run.perform }

        run.id
      end
    end
  end
end
