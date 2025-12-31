# frozen_string_literal: true

require_relative "plugin_definition"
require "nokogiri"

module Apricity
  module Plugins
    # A JUnitReporter plugin that consumes xml test reports and appends summary events to the job logs
    class JUnitReporter < PluginDefinition
      JUnitReportParsedEvent = Data.define(:node, :report, :parsed_at) do
        def type = :junit_report_parsed

        def pretty
          "parsed junit output for job #{node.job_name}: " \
            "tests=#{report.tests}, failures=#{report.failures}, " \
            "errors=#{report.errors}, skipped=#{report.skipped}"
        end
      end

      JUnitResult = Data.define(:test_name, :classname, :time, :status, :message)
      JUnitReport = Data.define(:tests, :failures, :errors, :skipped, :test_results)

      def initialize
        super(name: "junit-reporter", org: "apricity", version: "0.1.0")
      end

      def job_finished(context:, emitter:, options:)
        junit_file = options[:junit_report] || "junit.xml"
        artifact_key = options[:artifact_key] || "test-outputs"
        host_output_directory = context.artifact_outputs[artifact_key]
        junit_path = File.join(host_output_directory, junit_file)
        return unless File.exist?(junit_path)

        report = parse_junit_report(junit_path, context:, emitter:)
        annotate_job(report:, context:, emitter:)
      rescue StandardError => e
        warn "JUnitReporter: Error in after_job for job #{context.node.id}: #{e.message}"
        raise e
      end

      private

      def parse_junit_report(path, context:, emitter:)
        file = File.open(path)
        doc = Nokogiri::XML(file)
        report = parse_junit_report!(doc)
        file.close

        emitter[JUnitReportParsedEvent.new(node: context.node, report:, parsed_at: Time.now)]

        report
      end

      def parse_junit_report!(doc)
        test_suites = doc.xpath("//testsuite")
        totals = { tests: 0, failures: 0, errors: 0, skipped: 0 }
        test_suites.each do |suite|
          parse_suite(suite, totals)
        end
        JUnitReport[**totals, test_results: []]
      end

      def parse_suite(suite, totals)
        totals[:tests] += suite["tests"].to_i
        totals[:failures] += suite["failures"].to_i
        totals[:errors] += suite["errors"].to_i
        totals[:skipped] += suite["skipped"].to_i
      end

      def icon(report)
        if report.failures.positive? || report.errors.positive?
          "📕"
        else
          "📗"
        end
      end

      def annotation(report)
        {
          tests: report.tests,
          failures: report.failures,
          errors: report.errors,
          skipped: report.skipped,
          _icon: icon(report)
        }
      end

      def annotate_job(report:, context:, emitter:)
        annotation = annotation(report)
        emitter.call(
          JobExecution::Events::JobAnnotated[
            node: context.node,
            annotations: { test_results: annotation },
            annotated_at: Time.now
          ]
        )
      end
    end
  end
end
