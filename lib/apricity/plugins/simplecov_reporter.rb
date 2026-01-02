# frozen_string_literal: true

require_relative "plugin_definition"

module Apricity
  module Plugins
    # SimpleCov Reporter Plugin
    class SimplecovReporter < PluginDefinition
      SimpleCovReportParsedEvent = Data.define(:coverage_percent) do
        def type = :simplecov_report_parsed

        def pretty = "parsed simplecov report: coverage_percent=#{coverage_percent}"
      end

      def initialize(job_id: nil, options: {})
        super(name: "simplecov-reporter", org: "apricity", version: "0.1.0", job_id:, options:)
      end

      def job_finished(context:, emitter:, options: {}, event: nil)
        coverage_report = options.fetch(:coverage_report, ".last_run.json")
        artifact_key = options.fetch(:artifact_key, "coverage")
        host_output_directory = context.artifact_outputs[artifact_key]
        coverage_path = File.join(host_output_directory, coverage_report)

        return unless File.exist?(coverage_path)

        report = parse_simplecov_report(coverage_path, emitter:)
        annotate_job(report:, context:, emitter:)
      rescue StandardError => e
        warn "SimplecovReporter[#{event&.type}]: Error in after_job for job #{context.node.id}: #{e.message}"
        raise e
      end

      private

      def parse_simplecov_report(path, emitter:)
        file = File.open(path)
        data = JSON.parse(file.read)
        file.close

        coverage_percent = data["result"]["line"]
        emitter[SimpleCovReportParsedEvent.new(coverage_percent:)]

        { coverage_percent: }
      end

      def annotate_job(report:, context:, emitter:)
        coverage = report[:coverage_percent]
        emitter[JobExecution::Events::JobAnnotated[
          node: context.node,
          annotations: { coverage: { _icon: "📖", lines: "#{coverage}%" } },
          annotated_at: Time.now
        ]]
      end
    end
  end
end
