# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "can force run dependency with needs even if no input/output declared" do
      let(:pipeline) do
        PipelineBuilder
          .new("needs-ci")
          .action("ci") do |act|
            act.job("deploy", runs_on: container) do |job|
              job.demands("test")
              job.step("deploy", run: Script.new(source: "echo deploy"))
            end

            act.job("test", runs_on: container) do |job|
              job.step("test", run: Script.new(source: "echo test"))
            end
          end
          .to_pipeline
      end

      it "runs jobs in the correct order based on needs" do
        expect(job_order).to eq(%w[test deploy])
      end
    end
  end
end
