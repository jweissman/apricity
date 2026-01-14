# frozen_string_literal: true

require "yaml"

require "spec_helper"
require "apricity/pipeline/parser"
require "apricity/plugins/simplecov_reporter"

module Apricity
  module Plugins
    RSpec.describe SimplecovReporter do
      describe "registration" do
        before { PluginRegistry.instance.register(described_class) }

        let(:fixture_file_path) { "spec/fixtures/test-hello-pipeline.yaml" }
        let(:pipeline) { Apricity::Model::Pipeline.from_file(fixture_file_path) }
        let(:plugin_def) { pipeline.action(:test).job(:test).plugins.find { |p| p.name == "simplecov-reporter" } }

        it "attaches SimpleCovReporter plugin to test job" do
          expect(plugin_def.to_s).to eq("apricity/simplecov-reporter:latest")
        end

        describe "can dereference SimpleCovReporter plugin" do
          let(:registry) { Apricity::Plugins::PluginRegistry.instance }
          let(:plugin) { registry.get_plugin(plugin_def).new }

          it "fetches the correct plugin name" do
            expect(plugin.name).to eq("simplecov-reporter")
          end

          it "fetches the correct plugin org" do
            expect(plugin.org).to eq("apricity")
          end

          it "fetches the correct plugin version" do
            expect(plugin.version).to eq("0.1.0")
          end
        end
      end

      describe "simulated execution" do
        subject(:plugin) { described_class.new }

        # rubocop:disable RSpec/VerifiedDoubles
        let(:emitter) { double("emitter") }
        # rubocop:enable RSpec/VerifiedDoubles

        # let(:node) { instance_double(JobExecution::Node, job_name: "test-job") }
        let(:coverage_report_path) { "spec/fixtures/simplecov/.resultset.json" }
        let(:coverage_report_full_path) { File.expand_path(coverage_report_path) }

        before do
          allow(emitter).to receive(:[])
          plugin.parse_simplecov_report(coverage_report_full_path, emitter:)
        end

        # rubocop:disable RSpec/MultipleExpectations
        it "parses SimpleCov report and emits event" do
          expect(emitter).to have_received(:[]).with(
            an_instance_of(SimplecovReportModels::SimpleCovReportParsedEvent)
          ) do |event|
            expect(event.coverage_percent).to eq 77.62
          end
        end
        # rubocop:enable RSpec/MultipleExpectations
      end
    end
  end
end
