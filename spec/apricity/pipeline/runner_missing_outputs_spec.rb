# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "pipeline with missing required outputs" do
      let(:pipeline) do
        PipelineBuilder
          .new("missing-output")
          .action("ci") do |act|
            act.job("build", runs_on: container) do |job|
              job.output("version", :value)
              job.step("build", run: Script.new(source: "echo nope"))
            end
          end
          .to_pipeline
      end

      it "fails the job" do
        expect(outcomes.first.status).to eq("failure")
      end

      it "reports the missing output in the message" do
        expect(outcomes.first.message).to include("Declared output 'version' was not produced")
      end
    end
  end
end
