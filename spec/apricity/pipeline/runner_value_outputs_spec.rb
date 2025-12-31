# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "pipeline with value outputs and conditions" do
      let(:pipeline) do
        PipelineBuilder
          .new("values-ci")
          .action("ci") do |act|
            act.job("deploy", runs_on: container) do |job|
              job.input("version", :value)
              job.step("deploy", run: Script.new(source: "echo Deploying version $VERSION"))
            end
            act.job("build", runs_on: container) do |job|
              job.output("version", :value)
              job.step("build", run: Script.new(source: "echo version=1.2.3 >> $APRICITY_OUTPUT"))
            end
          end
          .to_pipeline
      end

      it_behaves_like "a successful pipeline"

      it "passes a value output from one job to another" do
        expect(outcomes.last.stdout).to include("Deploying version 1.2.3")
      end
    end
  end
end
