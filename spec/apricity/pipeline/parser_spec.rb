# frozen_string_literal: true

require "rspec"
require "spec_helper"
require "yaml"
require "apricity/pipeline/parser"

module Apricity
  module Pipeline
    RSpec.describe Parser do
      subject(:parser) { described_class }
      let(:pipeline) { Apricity::Model::Pipeline.from_yaml(file) }

      describe "parses test fixture pipeline" do
        let(:file) { File.read("spec/fixtures/test-fixture-pipeline.yaml") }

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

      describe "parses pipeline with matrix strategy" do
        let(:file) { File.read("spec/fixtures/test-matrix-pipeline.yaml") }
        let(:pipeline) { Apricity::Model::Pipeline.from_yaml(file) }
        let(:test_job) { pipeline.actions.first.jobs.find { |job| job.name == :test } }

        it "parses strategy matrix" do
          expect(test_job.strategy).to eq(
            Model::Strategy[matrix: { shard: [1, 2, 3] }]
          )
        end
      end

      describe "parses pipeline with services" do
        let(:file) { File.read("spec/fixtures/test-services-pipeline.yaml") }
        let(:pipeline) { Apricity::Model::Pipeline.from_yaml(file) }
        let(:test_job) { pipeline.actions.first.jobs.find { |job| job.name == :test } }

        let(:pg) do
          Model::Service[
            name: "db",
            image: "postgres:18",
            ports: ["5432:5432"],
            env_vars: { POSTGRES_USER: "testuser",
                        POSTGRES_PASSWORD: "testpass", POSTGRES_DB: "testdb" }
          ]
        end

        it "parses postgres service" do
          expect(test_job.services.first).to eq(pg)
        end

        it "parses redis service" do
          expect(test_job.services).to include(Model::Service[name: "redis",
                                                              image: "redis:7",
                                                              ports: ["6379:6379"]])
        end
      end

      describe "parses pipeline with action definitions" do
        let(:file) { File.read("spec/fixtures/test-actions-pipeline.yaml") }
        let(:pipeline) { Apricity::Model::Pipeline.from_yaml(file) }
        let(:test_job) { pipeline.actions.first.jobs.first }

        it "parses action use in job" do
          expect(test_job.steps.first.uses).to eq("apricity/checkout@v0")
        end

        it "parses action options in job" do
          expect(test_job.steps.first.with).to eq(repository: "jweissman/apricity", ref: "main")
        end
      end
    end
  end
end
