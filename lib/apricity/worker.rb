# frozen_string_literal: true

module Apricity
  # Worker module to run Apricity jobs
  module Worker
    VERSION = "0.1.0"

    KNOWN_PIPELINES = Dir.glob(File.join(__dir__, "../../example/**/apricity.yaml"))
                         .map { |f| Apricity::Model::Pipeline.from_file(f) }
                         .freeze

    # Simple registry of workers using Redis
    class Registry
      include Singleton

      def initialize
        @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
      end

      def list_workers
        @redis.smembers("apricity:workers").map do |worker_id|
          @redis.hgetall("apricity:worker:#{worker_id}").merge("worker_id" => worker_id)
        end
      end

      def register_worker(worker_id)
        @redis.hset("apricity:worker:#{worker_id}",
                    "started_at", Time.now.to_i,
                    "pid", Process.pid,
                    "version", VERSION,
                    "last_seen_at", Time.now.to_i)
        @redis.sadd("apricity:workers", worker_id)
      end

      def lease_ex = 30

      def heartbeat_worker(worker_id)
        @redis.hset("apricity:worker:#{worker_id}",
                    "last_seen_at", Time.now.to_i)
        # if we have run leases, extend their ttl
        current_run_id = @redis.hget("apricity:worker:#{worker_id}", "current_run_id")
        return nil unless current_run_id

        @redis.set("apricity:lease:#{current_run_id}", worker_id, ex: lease_ex)
      end

      def unregister_worker(worker_id)
        @redis.srem("apricity:workers", worker_id)
        @redis.del("apricity:worker:#{worker_id}")
      end

      def self.list_workers = instance.list_workers

      def run_lease(worker_id:, run_id:, pipeline_slug:)
        @redis.set("apricity:lease:#{run_id}", worker_id, ex: lease_ex)

        @redis.sadd("apricity:leases", run_id)
        @redis.hset("apricity:run_lease:#{run_id}",
                    "worker_id", worker_id,
                    "pipeline_slug", pipeline_slug)
        @redis.expire("apricity:run_lease:#{run_id}", lease_ex)
        @redis.hset("apricity:worker:#{worker_id}",
                    "last_seen_at", Time.now.to_i,
                    "current_run_id", run_id,
                    "current_pipeline_slug", pipeline_slug)
      end

      def release_run_lease(run_id)
        return unless run_id

        worker_id = @redis.get("apricity:lease:#{run_id}")
        @redis.del("apricity:lease:#{run_id}")
        @redis.srem("apricity:leases", run_id)
        @redis.del("apricity:run_lease:#{run_id}")
        return unless worker_id

        @redis.hdel("apricity:worker:#{worker_id}", "current_run_id", "current_pipeline_slug")
      end

      def lease_for_run(run_id)
        h = @redis.hgetall("apricity:run_lease:#{run_id}")
        return nil if h.empty?

        { run_id: run_id, worker_id: h["worker_id"], pipeline_slug: h["pipeline_slug"] }
      end

      def list_leases
        run_ids = @redis.smembers("apricity:leases")
        run_ids.map do |run_id|
          h = @redis.hgetall("apricity:run_lease:#{run_id}")
          { run_id: run_id, worker_id: h["worker_id"], pipeline_slug: h["pipeline_slug"] }
        end
      end

      def self.list_leases = instance.list_leases
    end

    class << self
      def find_pipeline_by_slug(slug) = KNOWN_PIPELINES.find { |p| p&.slug == slug }

      def process_jobs(worker_id:)
        puts "🚧  Worker #{worker_id} starting job processing loop..."
        loop do
          process_job(worker_id:)
        rescue StandardError => e
          warn "Worker #{worker_id}: Error processing job: #{e.class}: #{e.message}"
          warn e.backtrace.join("\n")
          sleep 1
        end
      end

      def process_job(worker_id:)
        msg = Apricity::Run::RunQueue.instance.pop
        run_id = msg[:run_id]
        pipeline_slug = msg[:pipeline_slug]
        Registry.instance.run_lease(worker_id:, run_id:, pipeline_slug:)
        pipeline = find_pipeline_by_slug(pipeline_slug)
        run = Apricity::Run::Instance.new(id: run_id, pipeline:, git_sha: nil, start_time: Time.now)

        with_duration("#{pipeline_slug} [#{run.id}]") { run.perform }
      ensure
        # remove lease
        Registry.instance.release_run_lease(run_id) if run_id
      end

      def with_duration(label, &)
        puts "#{label}..."
        t0 = Time.now
        result = yield
        t1 = Time.now
        duration = (t1 - t0)
        duration_seconds = (duration % 60).round(2)
        puts "Finished #{label} in #{duration_seconds}s."
        result
      end

      def heartbeat(worker_ids)
        puts "💓  Starting heartbeat for worker ids #{worker_ids}..."
        loop do
          sleep 10
          worker_ids.each do |worker_id|
            Registry.instance.heartbeat_worker(worker_id)
          end
        end
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def bootstrap
        Apricity.register_default_plugins
        Apricity.register_default_actions
        concurrency = ENV.fetch("APRICITY_WORKER_CONCURRENCY", "2").to_i
        worker_threads = []
        worker_ids = []
        concurrency.times do
          worker_id = generate_worker_id
          # puts "🚀  Starting Apricity worker #{worker_id}..."
          Registry.instance.register_worker(worker_id)
          worker_thread = Thread.new { process_jobs(worker_id:) }

          worker_threads << worker_thread
          worker_ids << worker_id
        end
        heartbeat_thread = Thread.new do
          heartbeat(worker_ids)
        end
        worker_threads.each(&:join)
      ensure
        worker_ids.each do |worker_id|
          Registry.instance.unregister_worker(worker_id)
        end

        heartbeat_thread&.kill
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      def generate_worker_id = SecureRandom.uuid
    end
  end
end
