# frozen_string_literal: true

require_relative "plugin_definition"
require "nokogiri"

module Apricity
  module Plugins
    # Consumes SBOM reports and annotates jobs with bill of materials data
    class SBOMReporter < PluginDefinition
      SBOMReportParsedEvent = Data.define(:node, :report, :parsed_at) do
        def type = :sbom_report_parsed

        def pretty
          "parsed SBOM report for job #{node.job_name}: " \
            "components=#{report.components.size}"
        end
      end

      SBOMReport = Data.define(:components, :licenses)

      def initialize(job_id: nil, options: {})
        super(name: "sbom-reporter", org: "apricity", version: "0.1.0", job_id:, options:)
      end

      def job_finished(context:, emitter:, options:, event: nil)
        sbom_file = options[:sbom_report] || "sbom.xml"
        artifact_key = options[:artifact_key] || "sbom"

        host_output_directory = context.artifact_outputs[artifact_key]
        sbom_path = File.join(host_output_directory, sbom_file)
        return unless File.exist?(sbom_path)

        report = parse_sbom_report(sbom_path, context:, emitter:)
        annotate_job(report:, context:, emitter:)
      rescue StandardError => e
        warn "SBOMReporter[#{event.type}]: Error in after_job for job #{context.node.id}: #{e.message}"
        raise e
      end

      private

      def parse_sbom_report(path, context:, emitter:)
        file = File.open(path)
        doc = Nokogiri::XML(file)
        report = parse_sbom_report!(doc)
        file.close

        emitter[SBOMReportParsedEvent.new(node: context.node, report:, parsed_at: Time.now)]

        report
      end

      def parse_sbom_report!(doc)
        ns = { "cdx" => doc.root.namespace.href }

        components = doc.xpath("//cdx:component", ns).map do |component_node|
          parse_component_node(component_node, ns)
        end

        licenses = Set.new
        components.each do |component|
          component[:licenses].each { |lic| licenses.add(lic) }
        end

        SBOMReport[components:, licenses: licenses.to_a]
      end

      def parse_component_node(component_node, namespace)
        name = component_node.at_xpath("cdx:name", namespace)&.text || "unknown"
        version = component_node.at_xpath("cdx:version", namespace)&.text || "unknown"
        component_type = component_node["type"] || "unknown"

        { name:, version:, type: component_type, licenses: parse_component_licenses(component_node, namespace) }
      end

      def parse_component_licenses(component_node, namespace)
        licenses = []

        # SPDX IDs
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:id", namespace).map(&:text)

        # Human-readable names
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:name", namespace).map(&:text)

        # SPDX expressions
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:expression", namespace).map(&:text)

        licenses.uniq
      end

      def annotate_job(report:, context:, emitter:)
        emitter[JobExecution::Events::JobAnnotated.new(
          node: context.node,
          annotations: { "sbom-report" => annotated(report) },
          annotated_at: Time.now
        )]
      end

      def annotated(report)
        {
          _icon: "📦",
          components: report.components.size,
          licenses: report.licenses.join(", ")
        }
      end
    end
  end
end
