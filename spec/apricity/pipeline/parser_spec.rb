# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "apricity/pipeline/parser"

module Apricity
  module Pipeline
    RSpec.describe Parser do
      subject(:parser) { described_class }

      let(:file) { File.read("spec/fixtures/test-fixture-pipeline.yaml") }
      let(:pipeline) { Apricity::Model::Pipeline.from_yaml(file) }

      it "parses action names" do
        expect(pipeline.actions.map(&:name)).to eq(%i[check])
      end

      it "parses job names" do
        expect(pipeline.actions.first.jobs.map(&:name)).to eq(%i[quality lint test])
      end

      describe "parses lint step commands" do
        let(:lint_job) { pipeline.actions.first.jobs.find { |job| job.name == :lint } }
        let(:first_step) { lint_job.steps.first }
        let(:next_step) { lint_job.steps[1] }

        it "parses first step command lines" do
          expect(first_step.run.source_lines.map(&:chomp)).to eq([
                                                                   "bundle config set --local path 'vendor/bundle'",
                                                                   "bundle install"
                                                                 ])
        end

        it "parses next step command lines" do
          expect(next_step.run.source_lines.map(&:chomp)).to eq([
                                                                  "bundle exec rubocop"
                                                                ])
        end
      end

      describe "parses test job" do
        let(:test_job) { pipeline.actions.first.jobs.find { |job| job.name == :test } }

        it "parses job steps" do
          expect(test_job.steps.map(&:name)).to eq(["Bundle install", "Run tests"])
        end

        it "parses outputs" do
          expect(test_job.outputs).to eq([
                                           Apricity::Model::Output["test-outputs", :artifact]
                                         ])
        end

        describe "parses plugins" do
          let(:plugin) { test_job.plugins.first }

          it "parses plugin name, org, version" do
            expect(plugin.to_s).to eq("apricity/example-plugin:latest")
          end

          it "parses plugin config" do
            expect(plugin.with).to eq({ "example-key": "example-value" })
          end
        end

        describe "parses commands" do
          it "parses first step command lines" do
            first_step = test_job.steps.first
            expect(first_step.run.source_lines).to eq([
                                                        "bundle config set --local path 'vendor/bundle'",
                                                        "bundle install"
                                                      ])
          end

          it "parses next step command lines" do
            next_step = test_job.steps[1]
            expect(next_step.run.source_lines).to eq([
                                                       "bundle exec rspec --fail-fast --format progress"
                                                     ])
          end
        end
      end
    end
  end
end
