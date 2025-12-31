# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

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
              job.step("deploy", run: Script.new(source: "echo deploy"))
            end

            act.job("test1", runs_on: container) do |job|
              job.output("test1_result", :value)
              job.step("test1", run: Script.new(source: "exit 1"))
            end

            act.job("test2", runs_on: container) do |job|
              job.output("test2_result", :value)
              job.step("test2", run: Script.new(source: "echo test2_result=ok >> $APRICITY_OUTPUT"))
            end
          end
          .to_pipeline
      end

      it "runs jobs in the correct order based on dependencies" do
        expect(job_order).to eq(%w[test1 test2 deploy]).or eq(%w[test2 test1 deploy])
      end

      it "fails the first test job" do
        expect(outcomes.find { |e| e.job == "test1" }).to be_failed
      end

      it "succeeds the second test job" do
        expect(outcomes.find { |e| e.job == "test2" }).to be_successful
      end

      it "does not run dependent jobs if conditions are not met" do
        expect(outcomes.last).to be_skipped
      end
    end
  end
end
