# frozen_string_literal: true

require_relative "plugin_definition"
require "nokogiri"

module Apricity
  module Plugins
    # A JUnitReporter plugin that consumes xml test reports and appends summary events to the job logs
    class JUnitReporter < PluginDefinition
      JUnitReportParsedEvent = Data.define(:node, :parsed_at) do
        def type = :junit_report_parsed
        def pretty = "parsed junit output for job #{node.job_name}"
      end

      def initialize
        super(name: "junit-reporter", org: "apricity", version: "0.1.0")
      end

      def job_finished(context:, emitter:, options:)
        $stdout.puts "JUnitReporter: after_job hook for job #{context.node.id} got config: #{options.inspect}"
        junit_file = options[:junit_report] || "junit.xml"
        junit_path = File.join(context.artifacts_dir, junit_file)
        unless File.exist?(junit_path)
          $stdout.puts "JUnitReporter: No junit report found at #{junit_path}"
          debugger
          return
        end
        parse_junit_report(junit_path, context:, emitter:)
      rescue StandardError => e
        warn "JUnitReporter: Error in after_job for job #{context.node.id}: #{e.message}"
        raise e
      end

      private

      def parse_junit_report(path, context:, emitter:)
        $stdout.puts "JUnitReporter: parsing junit report at #{path} for job #{context.node.id}"

        # use nokogiri to parse the junit xml
        file = File.open(path)
        doc = Nokogiri::XML(file)
        test_suites = doc.xpath("//testsuite")
        total_tests = 0
        total_failures = 0
        total_errors = 0
        total_skipped = 0
        test_suites.each do |suite|
          total_tests += suite["tests"].to_i
          total_failures += suite["failures"].to_i
          total_errors += suite["errors"].to_i
          total_skipped += suite["skipped"].to_i
        end
        total_passed = total_tests - total_failures - total_errors - total_skipped

        $stdout.puts "JUnitReporter: Test Summary for job #{context.node.id}:"
        $stdout.puts "  Total Tests: #{total_tests}"
        $stdout.puts "  Failures: #{total_failures}"
        $stdout.puts "  Errors: #{total_errors}"
        $stdout.puts "  Skipped: #{total_skipped}"
        $stdout.puts "  Passed: #{total_passed}"

        file.close

        emitter[JUnitReportParsedEvent.new(node: context.node, parsed_at: Time.now)]
      end
    end
  end
end
