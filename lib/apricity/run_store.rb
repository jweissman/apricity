# frozen_string_literal: true

module Apricity
  # In-memory store for runs
  class RunStore
    RunRecord = Data.define(
      :id, :pipeline_slug, :pipeline_name,
      :git_sha, :status, :created_at
    ) do
      def to_s = "Run #{id} (Pipeline: #{pipeline_slug}, Created at: #{created_at})"

      def self.from_run(run)
        new(
          id: run.id,
          pipeline_slug: run.pipeline.slug,
          pipeline_name: run.pipeline.name,
          git_sha: run.git_sha || "unknown",
          status: "pending",
          created_at: Time.now
        )
      end

      def start_time = created_at
      def started_at = created_at
    end

    # In memory backend implementation
    class InMemoryBackend
      def initialize = @runs = {}
      def add_run(run) = @runs[run.id] = run
      def get_run(run_id) = @runs[run_id]
      # Return runs in reverse order (newest first) to match Redis backend behavior
      def list_runs = @runs.values.reverse
      def set_run_status(run_id, status) = @runs[run_id]&.status = status
    end

    # Redis backend implementation
    class RedisBackend
      def initialize(redis:)
        @redis = redis
      end

      def add_run(record)
        # puts "Adding run with id=#{record.id} to Redis store (pipeline: #{record.pipeline_slug}) -- #{record}"
        redis.hset(key(record.id),
                   "id", record.id,
                   "pipeline_slug", record.pipeline_slug,
                   "pipeline_name", record.pipeline_name,
                   "git_sha", record.git_sha,
                   "status", record.status,
                   "created_at", record.created_at.to_i)

        redis.lrem("apricity:runs", 0, record.id) # remove any existing duplicates
        redis.lpush("apricity:runs", record.id)
      end

      def get_run(run_id)
        h = redis.hgetall(key(run_id))
        return nil if h.empty?

        RunRecord.new(
          id: h["id"],
          pipeline_slug: h["pipeline_slug"],
          pipeline_name: h["pipeline_name"],
          git_sha: h["git_sha"],
          status: h["status"] || "pending",
          created_at: Time.at(h["created_at"].to_i)
        )
      end

      def set_run_status(run_id, status)
        redis.hset(key(run_id), "status", status)
      end

      def list_runs(limit: 50)
        ids = redis.lrange("apricity:runs", 0, limit - 1)
        ids.filter_map { |id| get_run(id) }
      end

      private

      attr_reader :redis

      def key(id) = "apricity:run:#{id}"
    end

    include Singleton

    def initialize(backend: RedisBackend.new(
      redis: Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    ))
      # InMemoryBackend.new)
      @backend = backend
    end

    def add_run(run) = backend.add_run(RunRecord.from_run(run))
    def add_run_record(record) = backend.add_run(record)
    def get_run(run_id) = backend.get_run(run_id)
    def list_runs = backend.list_runs
    def set_run_status(run_id, status) = backend.set_run_status(run_id, status.to_s)

    def apply_event(run_id:, event:)
      record = get_run(run_id)
      return unless record

      case event.type
      when :pipeline_started then set_run_status(run_id, "running")
      when :pipeline_finished
        set_run_status(run_id, event.status.to_s)
      end
    end

    private

    attr_reader :backend
  end
end
