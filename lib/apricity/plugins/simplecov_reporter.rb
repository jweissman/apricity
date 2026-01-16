# frozen_string_literal: true

require "simplecov"
require_relative "plugin_definition"

module Apricity
  module Plugins
    module SimplecovReportModels
      SimpleCovReportParsedEvent = Data.define(:coverage_percent) do
        def type = :simplecov_report_parsed

        def pretty = "parsed simplecov report: coverage_percent=#{coverage_percent}"
      end
    end

    # Parser module for SimpleCov JSON reports
    module SimplecovParser
      def collate_reports(paths, _context: nil)
        merged = {}

        paths.each do |path|
          data = JSON.parse(File.read(path))
          data.each_value do |run|
            merge_coverage(run, merged)
          end
        end

        coverage_stats merged
      end

      def merge_coverage(run, merged)
        run["coverage"]&.each do |file, info|
          merge_coverage_file(info, file, merged)
        end
      end

      def merge_coverage_file(info, file, merged)
        lines = info["lines"]

        merged[file] ||= { "lines" => [] }
        target = merged[file]["lines"]

        max = [target.length, lines.length].max

        merged[file]["lines"] = (0...max).map do |i|
          merge_lines(target, lines, i)
        end
      end

      def merge_lines(target, lines, index)
        a = target[index]
        b = lines[index]

        return 1 if a&.positive? || b&.positive?
        return 0 if a&.zero? || b&.zero?

        nil
      end

      def coverage_stats(merged)
        stats = { total: 0, covered: 0 }

        merged.each_value do |info|
          info["lines"].each do |line|
            next unless line

            stats[:total] += 1
            stats[:covered] += 1 if line == 1
          end
        end

        stats.merge(coverage_percent: stats[:total].zero? ? 0.0 : (stats[:covered].to_f / stats[:total] * 100).round(2))
      end
    end

    # SimpleCov Reporter Plugin
    class SimplecovReporter < PluginDefinition
      include SimplecovParser

      def initialize(job_id: nil, options: {})
        super(name: "simplecov-reporter", org: "apricity", version: "0.1.0", job_id:, options:)
      end

      def pipeline_finished(context:, emitter:, options: {}, event: nil)
        # warn "Context: #{context.inspect}"
        # debugger
        nodes_paths = analyze_nodes_paths(event.outputs_by_node, options)
        paths = nodes_paths.values.flatten.select { File.exist?(it) }

        stats = collate_reports(paths) # nodes_paths.values.flatten)
        coverage_percent = stats[:coverage_percent]
        warn "SimplecovReporter[pipeline_finished]: Merged coverage: #{coverage_percent}% from #{paths.size} reports."

        emitter[SimplecovReportModels::SimpleCovReportParsedEvent.new(coverage_percent:)]

        annotate_pipeline(report: stats, context:, emitter:)
      end

      # old job finished using last_run.json per job
      # def job_finished(context:, emitter:, options: {}, event: nil)
      #   coverage_report = options.fetch(:coverage_report, ".last_run.json")
      #   artifact_key = options.fetch(:artifact_key, "coverage")
      #   host_output_directory = context.artifact_outputs[artifact_key]
      #   return unless assert_present(host_output_directory,
      #                                "SimplecovReporter[#{event&.type}]: No coverage found \
      #                                for job #{context.node.id}")

      #   parse_and_annotate_job(File.join(host_output_directory, coverage_report), context:, emitter:)
      # rescue StandardError => e
      #   warn "SimplecovReporter[#{event&.type}]: Error in after_job for job #{context.node.id}: #{e.message}"
      #   raise e
      # end

      # new job finished using resultset.json per job
      def job_finished(context:, emitter:, options: {}, event: nil)
        coverage_report = options.fetch(:coverage_report, ".resultset.json")
        artifact_key = options.fetch(:artifact_key, "coverage")
        host_output_directory = context.artifact_outputs[artifact_key]
        return unless assert_present(host_output_directory,
                                     "SimplecovReporter[#{event&.type}]: No coverage found for job #{context.node.id}")

        parse_and_annotate_job(File.join(host_output_directory, coverage_report), context:, emitter:)
      rescue StandardError => e
        warn "SimplecovReporter[#{event&.type}]: Error in after_job for job #{context.node.id}: #{e.message}"
        raise e
      end

      def parse_simplecov_report(path, emitter:)
        file = File.open(path)
        data = JSON.parse(file.read)
        file.close

        unless assert_present(data && data.is_a?(Hash),
                              "MergeCoverage: Invalid SimpleCov .resultset.json report format in #{path}")
          return { coverage_percent: 0 }
        end

        # debugger
        coverage_percent = collate_reports([path])[:coverage_percent]
        emitter[SimplecovReportModels::SimpleCovReportParsedEvent.new(coverage_percent:)]
        { coverage_percent: }
      end

      private

      def assert_present(value, message)
        warn message unless value

        value
      end

      def analyze_nodes_paths(outputs_by_node, options)
        pattern = options[:coverage_reports] || options[:coverage_report]
        nodes_paths = {}
        outputs_by_node.each do |node_id, outputs|
          artifact_key = options[:artifact_key] || "coverage"
          host_output_directory = outputs[artifact_key]
          next unless host_output_directory && pattern

          nodes_paths[node_id] = Dir.glob(File.join(host_output_directory, pattern))
        end
        nodes_paths
      end

      def parse_and_annotate_job(coverage_path, context:, emitter:)
        unless File.exist?(coverage_path)
          warn "Warning -- SimplecovReporter: No SimpleCov report file at #{coverage_path}"
          return
        end

        report = parse_simplecov_report(coverage_path, emitter:)
        annotate_job(report:, context:, emitter:)
      end

      def annotate_job(report:, context:, emitter:)
        # debugger
        coverage = report[:coverage_percent]
        emitter[JobExecution::Events::JobAnnotated[
          node: context.node,
          annotations: { coverage: { _icon: "📖", lines: "#{coverage}%" } },
          annotated_at: Time.now
        ]]
      end

      def annotation(report)
        {
          _icon: "📖",
          lines: "#{report[:coverage_percent]}%"
        }
      end

      def annotate_pipeline(report:, context:, emitter:)
        return if report[:coverage_percent].zero?

        annotation = annotation(report)

        emitter.call(
          JobExecution::Events::PipelineAnnotated[
            pipeline_name: context.pipeline_name,
            annotations: { coverage: annotation },
            annotated_at: Time.now
          ]
        )
      end
    end
  end
end
