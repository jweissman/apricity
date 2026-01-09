# frozen_string_literal: true

require_relative "plugin_definition"
require "nokogiri"

module Apricity
  module Plugins
    # Events related to JUnit reporting
    module JUnitReportModels
      JUnitReportParsedEvent = Data.define(:node, :report, :parsed_at) do
        def type = :junit_report_parsed

        def pretty
          "parsed junit output for job #{node.job_name}: " \
            "tests=#{report.tests}, failures=#{report.failures}, " \
            "errors=#{report.errors}, skipped=#{report.skipped}"
        end
      end

      JUnitResult = Data.define(:test_name, :classname, :time, :status, :message)
      JUnitReport = Data.define(:tests, :failures, :errors, :skipped, :test_results) do
        def merge(other)
          JUnitReport[
            tests: tests + other.tests,
            failures: failures + other.failures,
            errors: errors + other.errors,
            skipped: skipped + other.skipped,
            test_results: test_results + other.test_results
          ]
        end
      end
    end

    # Parser module for JUnit XML reports
    module JUnitParser
      def parse_junit_report(path, node:, emitter:)
        file = File.open(path)
        doc = Nokogiri::XML(file)
        report = parse_junit_report!(doc)
        file.close

        emitter[JUnitReportModels::JUnitReportParsedEvent.new(node:, report:, parsed_at: Time.now)]

        report
      end

      def parse_junit_report!(doc)
        test_suites = doc.xpath("//testsuite")
        totals = { tests: 0, failures: 0, errors: 0, skipped: 0 }
        test_suites.each do |suite|
          parse_suite(suite, totals)
        end
        JUnitReportModels::JUnitReport[**totals, test_results: []]
      end

      def parse_suite(suite, totals)
        totals[:tests] += suite["tests"].to_i
        totals[:failures] += suite["failures"].to_i
        totals[:errors] += suite["errors"].to_i
        totals[:skipped] += suite["skipped"].to_i
      end
    end

    # A JUnitReporter plugin that consumes xml test reports and appends summary events to the job logs
    class JUnitReporter < PluginDefinition
      include JUnitReportModels
      include JUnitParser

      attr_reader :job_id, :job_name

      def initialize(job_id: nil, options: {})
        super(name: "junit-reporter", org: "apricity", version: "0.1.0", job_id:, options:)
      end

      def pipeline_finished(context:, emitter:, event:, options: @options)
        nodes_paths = analyze_nodes_paths(event.outputs_by_node, options)
        if nodes_paths.empty?
          warn "Warning -- JUnitReporter: No JUnit report files detected in pipeline outputs."
          return
        end
        parse_and_annotate_reports(nodes_paths, context:, emitter:)
      end

      def analyze_nodes_paths(outputs_by_node, options)
        pattern = options[:junit_reports] || options[:junit_report]
        nodes_paths = {}
        outputs_by_node.each do |node_id, outputs|
          artifact_key = options[:artifact_key] || "test-outputs"
          host_output_directory = outputs[artifact_key]
          next unless host_output_directory

          nodes_paths[node_id] = Dir.glob(File.join(host_output_directory, pattern))
        end
        nodes_paths
      end

      def job_finished(context:, emitter:, options:, event:)
        # Console.debug self, "job_finished called with options: #{options.inspect} / #{event.type}"
        junit_file = options[:junit_report] || "junit.xml"
        artifact_key = options[:artifact_key] || "test-outputs"
        host_output_directory = context.artifact_outputs[artifact_key]
        return unless host_output_directory

        junit_path = File.join(host_output_directory, junit_file)

        if File.exist?(junit_path)
          parse_junit_report(junit_path, node: context.node, emitter:)
        else
          warn "Warning -- JUnitReporter: No JUnit report file at #{junit_path}"
        end
      end

      def parse_and_annotate_reports(nodes_paths, context:, emitter:)
        reports = nodes_paths.flat_map do |node_id, junit_paths|
          junit_paths.flat_map do |junit_path|
            parse_junit_report(junit_path, node: node_id, emitter: ->(*_args) {})
          end
        end

        annotate_pipeline(report: merge_reports(reports), context:, emitter:)
      rescue StandardError => e
        location = context.respond_to?(:node) ? "job #{context.node.id}" : "pipeline #{context.pipeline_name}"
        warn "JUnitReporter: Error in after_job for #{location}: #{e.message}"
        raise e
      end

      def merge_reports(reports)
        reports.reduce(JUnitReport[tests: 0, failures: 0, errors: 0, skipped: 0, test_results: []]) do |acc, report|
          acc.merge(report)
        end
      end

      private

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

      def annotate_pipeline(report:, context:, emitter:)
        annotation = annotation(report)

        # debugger
        emitter.call(
          JobExecution::Events::PipelineAnnotated[
            pipeline_name: context.pipeline_name,
            annotations: { test_results: annotation },
            annotated_at: Time.now
          ]
        )
      end
    end
  end
end
