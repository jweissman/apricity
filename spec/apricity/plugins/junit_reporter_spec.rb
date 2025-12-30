# frozen_string_literal: true

require "yaml"
require "spec_helper"
require "apricity/pipeline/parser"
require "apricity/plugins/junit_reporter"

module Apricity
  module Plugins
    RSpec.describe JUnitReporter do
      before { described_class.new.register }

      let(:fixture_file_path) { "spec/fixtures/test-hello-pipeline.yaml" }
      let(:pipeline) { Apricity::Model::Pipeline.from_file(fixture_file_path) }
      let(:plugin_def) { pipeline.action(:test).job(:test).plugins.find { |p| p.name == "junit-reporter" } }

      it "attaches JUnitReporter plugin to test job" do
        expect(plugin_def.to_s).to eq("apricity/junit-reporter:latest")
      end

      describe "can dereference JUnitReporter plugin" do
        let(:registry) { Apricity::Plugins::PluginRegistry.instance }
        let(:plugin) { registry.get_plugin(plugin_def) }

        it "fetches the correct plugin name" do
          expect(plugin.name).to eq("junit-reporter")
        end

        it "fetches the correct plugin org" do
          expect(plugin.org).to eq("apricity")
        end

        it "fetches the correct plugin version" do
          expect(plugin.version).to eq("0.1.0")
        end
      end

      describe "executes JUnitReporter plugin" do
        before do
          @events = []
          runner.run { @events << it }
        end

        let(:runner) { Apricity::Pipeline::Runner.new(pipeline:) }

        it "runs after_job hook without errors", skip: "will not work by default under apricot (since DinDinD)",
                                                 tag: "integration" do
          expect(@events.any? { |e| e.type == :junit_report_parsed }).to be true
        end
      end
    end
  end
end
