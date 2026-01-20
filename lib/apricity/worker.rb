# frozen_string_literal: true

module Apricity
  # Worker module to run Apricity jobs
  module Worker
    VERSION = "0.1.0"

    KNOWN_PIPELINES = Dir.glob(File.join(__dir__, "../../example/**/apricity.yaml"))
                         .map { |f| Apricity::Model::Pipeline.from_file(f) }
                         .freeze

    class << self
      def find_pipeline_by_slug(slug) = KNOWN_PIPELINES.find { |p| p&.slug == slug }

      def process_jobs = loop { process_job }

      def process_job
        msg = Apricity::Run::RunQueue.instance.pop
        run_id = msg[:run_id]
        pipeline_slug = msg[:pipeline_slug]
        pipeline = find_pipeline_by_slug(pipeline_slug)
        run = Apricity::Run::Instance.new(id: run_id, pipeline:, git_sha: nil, start_time: Time.now)

        with_duration("#{pipeline_slug} [#{run.id}]") do
          run.perform
        end
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

      def bootstrap
        Apricity.register_default_plugins
        Apricity.register_default_actions

        puts "🚀  Starting Apricity worker..."
        concurrency = ENV.fetch("APRICITY_WORKER_CONCURRENCY", "2").to_i
        workers = []
        concurrency.times do
          workers << Thread.new { process_jobs }
        end

        # puts "❄️  Waiting for jobs [concurrency=#{concurrency}]..."

        workers.each(&:join)
      end
    end
  end
end
