# frozen_string_literal: true

require "spec_helper"

# shared examples for apricity pipelines
RSpec.shared_examples "a successful pipeline" do
  it "runs all successfully" do
    pipeline_runner = Apricity::PipelineRunner.new(pipeline)
    pipeline_outcomes = pipeline_runner.run!
    expect(pipeline_outcomes).to all(be_a(Apricity::Model::StepOutcome))
    expect(pipeline_outcomes.size).to eq(pipeline.total_steps)
    expect(pipeline_outcomes).to all(be_successful)
  end
end

# rubocop:disable Metrics/ModuleLength
module Apricity
  include Model
  include Model::Builders

  # rubocop:disable Metrics/BlockLength
  RSpec.describe Apricity do
    describe "runtime pipeline execution" do
      subject(:runner) { PipelineRunner.new(pipeline) }
      let(:container) { Container.new("ruby", "3.4") }
      let(:outcomes) { runner.run! }
      let(:job_order) { outcomes.map(&:job).uniq }
      let(:first_outcome) { outcomes.first }
      let(:deploy_outcome) { outcomes.find { |e| e.job == "deploy" } }

      describe "simple pipeline" do
        let(:command) { Script.new(lines: ["ruby -e 'puts \"Hello, World!\"'"]) }
        let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

        it_behaves_like "a successful pipeline"

        it "executes scripts in the given container" do
          expect(first_outcome.container.name).to eq("ruby")
          expect(first_outcome.container.version).to eq("3.4")
          expect(first_outcome.script).to eq("ruby -e 'puts \"Hello, World!\"'")
          expect(first_outcome.stdout).to eq("Hello, World!\n")
        end
      end

      describe "echo pipeline" do
        let(:command) { Script.new(lines: ["echo 'Hello, Apricity!'"]) }
        let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

        it_behaves_like "a successful pipeline"

        it "captures simple echo output" do
          expect(first_outcome.stdout).to eq("Hello, Apricity!\n")
        end
      end

      describe "failing pipeline" do
        let(:command) { Script.new(lines: ["exit 1"]) }
        let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

        it "captures failure of a command" do
          expect(first_outcome).to be_failed
          expect(first_outcome.message).to include("Step execute failed")
        end
      end

      describe "steps share container" do
        let(:pipeline) do
          PipelineBuilder
            .new("shared-container")
            .action("ci") do |act|
              act.job("build", runs_on: container) do |job|
                job.step("step1", run: Script.new(lines: ["echo 'Step 1' > /work/step.txt"]))
                job.step("step2", run: Script.new(lines: ["cat /work/step.txt"]))
              end
            end
            .to_pipeline
        end

        it_behaves_like "a successful pipeline"

        it "allows steps to share state via the container filesystem" do
          expect(outcomes.last.stdout).to eq("Step 1\n")
        end
      end

      describe "pipeline with dependencies" do
        let(:build_cmd) { Script.new(lines: ["echo data=ok >> $APRICITY_OUTPUT"]) }
        let(:test_cmd) { Script.new(lines: ["echo test"]) }
        let(:pipeline) do
          PipelineBuilder
            .new("dag-ci")
            .action("ci") do |act|
              act.job("test", runs_on: container) do |job|
                job.input("data", :value)
                job.step("test", run: test_cmd)
              end
              act.job("build", runs_on: container) do |job|
                job.output("data", :value)
                job.step("build", run: build_cmd)
              end
            end
            .to_pipeline
        end

        # NOTE: we get a warning on the build step because we do not produce artifacts yet
        # it_behaves_like "a successful pipeline"

        it "orders jobs by artifact dependencies, not declaration order" do
          expect(job_order).to eq(%w[build test])
        end
      end

      describe "pipeline with value outputs and conditions" do
        let(:build_cmd) { Script.new(lines: ["echo version=1.2.3 >> $APRICITY_OUTPUT"]) }
        let(:deploy_cmd) { Script.new(lines: ["echo Deploying version $VERSION"]) }

        let(:pipeline) do
          PipelineBuilder
            .new("values-ci")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.input("version", :value)
                job.step("deploy", run: deploy_cmd)
              end
              act.job("build", runs_on: container) do |job|
                job.output("version", :value)
                job.step("build", run: build_cmd)
              end
            end
            .to_pipeline
        end

        it_behaves_like "a successful pipeline"

        it "passes a value output from one job to another" do
          expect(deploy_outcome.stdout).to include("Deploying version 1.2.3")
        end
      end

      describe "pipeline with missing required outputs" do
        let(:pipeline) do
          PipelineBuilder
            .new("missing-output")
            .action("ci") do |act|
              act.job("build", runs_on: container) do |job|
                job.output("version", :value)
                job.step("build", run: Script.new(lines: ["echo nope"]))
              end
            end
            .to_pipeline
        end

        it "fails a job if a declared value output is not produced" do
          # debugger
          expect(first_outcome.status).to eq("failure")
          expect(first_outcome.message).to include("Declared output 'version' was not produced")
        end
      end

      describe "pipeline with unmet conditions" do
        let(:pipeline) do
          PipelineBuilder
            .new("conditional")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.input("version", :value)
                job.condition(Conditions::Equals.new("version", "1.2.3"))
                job.step("deploy", run: Script.new(lines: ["echo deploy"]))
              end
              act.job("build", runs_on: container) do |job|
                job.output("version", :value)
                job.step("build", run: Script.new(lines: ["echo version=0.1.0 >> $APRICITY_OUTPUT"]))
              end
            end
            .to_pipeline
        end

        it "skips a job when a value condition is not met" do
          expect(job_order).to eq(%w[build deploy])
          expect(first_outcome).to be_successful
          expect(deploy_outcome).to be_skipped
          expect(deploy_outcome.message).to include("conditions_unmet")
        end
      end

      describe "fan-out/fan-in pipeline" do
        # build -> test1
        #       -> test2
        # test1 + test2 -> deploy
        let(:pipeline) do
          PipelineBuilder
            .new("fanout-ci")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.input("test1_result", :value)
                job.input("test2_result", :value)
                job.step("deploy", run: Script.new(lines: ["echo deploy"]))
              end

              act.job("test1", runs_on: container) do |job|
                job.input("dist", :artifact)
                job.output("test1_result", :value)
                job.step("test1", run: Script.new(lines: ["echo test1_result=ok >> $APRICITY_OUTPUT"]))
              end

              act.job("test2", runs_on: container) do |job|
                job.input("dist", :artifact)
                job.input("test1_result", :value)
                job.output("test2_result", :value)
                job.step("test2", run: Script.new(lines: ["echo test2_result=ok >> $APRICITY_OUTPUT"]))
              end

              act.job("build", runs_on: container) do |job|
                job.output("dist", :artifact)
                job.step("build", run: Script.new(lines: [
                                                    "mkdir -p dist",
                                                    "echo build > artifacts/dist/artifact.txt"
                                                  ]))
              end
            end
            .to_pipeline
        end

        it_behaves_like "a successful pipeline"

        it "orders jobs correctly for fan-out/fan-in scenario" do
          expect(job_order).to eq(%w[build test1 test2 deploy])
        end
      end

      describe "partial pipeline execution" do
        # test1 fails
        # test2 succeeds
        # deploy should not run
        let(:pipeline) do
          PipelineBuilder
            .new("partial-ci")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.input("test1_result", :value)
                job.input("test2_result", :value)
                job.condition(Conditions::Equals.new("test1_result", "ok"))
                job.condition(Conditions::Equals.new("test2_result", "ok"))
                job.step("deploy", run: Script.new(lines: ["echo deploy"]))
              end

              act.job("test1", runs_on: container) do |job|
                job.output("test1_result", :value)
                job.step("test1", run: Script.new(lines: ["exit 1"]))
              end

              act.job("test2", runs_on: container) do |job|
                job.output("test2_result", :value)
                job.step("test2", run: Script.new(lines: ["echo test2_result=ok >> $APRICITY_OUTPUT"]))
              end
            end
            .to_pipeline
        end

        it "does not run dependent jobs if conditions are not met" do
          expect(job_order).to eq(%w[test1 test2 deploy])
          expect(outcomes.find { |e| e.job == "test1" }).to be_failed
          expect(outcomes.find { |e| e.job == "test2" }).to be_successful
          expect(deploy_outcome).to be_skipped
        end
      end

      describe "can force run dependency with needs even if no input/output declared" do
        let(:pipeline) do
          PipelineBuilder
            .new("needs-ci")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.demands("test")
                job.step("deploy", run: Script.new(lines: ["echo deploy"]))
              end

              act.job("test", runs_on: container) do |job|
                job.step("test", run: Script.new(lines: ["echo test"]))
              end
            end
            .to_pipeline
        end

        it "runs jobs in the correct order based on needs" do
          expect(job_order).to eq(%w[test deploy])
        end
      end

      describe "downstream job can read files produced by an upstream job via an artifact directory" do
        let(:pipeline) do
          PipelineBuilder
            .new("artifact-dir-ci")
            .action("ci") do |act|
              act.job("deploy", runs_on: container) do |job|
                job.input("dist", :artifact)
                job.step("deploy", run: Script.new(lines: ["cat artifacts/dist/artifact.txt"]))
              end

              act.job("build", runs_on: container) do |job|
                job.output("dist", :artifact)
                job.step("build", run: Script.new(lines: [
                                                    "mkdir -p artifacts/dist",
                                                    "echo build > artifacts/dist/artifact.txt"
                                                  ]))
              end
            end
            .to_pipeline
        end

        it "allows downstream jobs to read files from upstream jobs' artifact directories" do
          expect(deploy_outcome.stdout).to eq("build\n")
        end
      end
    end
  end
  # rubocop:enable Metrics/BlockLength
end
# rubocop:enable Metrics/ModuleLength
