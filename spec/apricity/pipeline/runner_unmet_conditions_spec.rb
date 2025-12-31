# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "pipeline with unmet conditions" do
      let(:pipeline) do
        PipelineBuilder
          .new("conditional")
          .action("ci") do |act|
            act.job("deploy", runs_on: container) do |job|
              job.input("version", :value)
              job.condition(Conditions::Equals.new("version", "1.2.3"))
              job.step("deploy", run: Script.new(source: "echo deploy"))
            end
            act.job("build", runs_on: container) do |job|
              job.output("version", :value)
              job.step("build", run: Script.new(source: "echo version=0.1.0 >> $APRICITY_OUTPUT"))
            end
          end
          .to_pipeline
      end

      it "has expected job order" do
        expect(job_order).to eq(%w[build deploy])
      end

      it "build is successful" do
        expect(outcomes.first).to be_successful
      end

      it "deploy is skipped" do
        expect(outcomes.last).to be_skipped
      end

      it "reports the unmet condition in the message" do
        expect(outcomes.last.message).to include("conditions_unmet")
      end
    end
  end
end
