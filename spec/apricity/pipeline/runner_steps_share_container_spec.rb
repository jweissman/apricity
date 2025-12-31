# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "steps share container" do
      let(:pipeline) do
        PipelineBuilder
          .new("shared-container")
          .action("ci") do |act|
            act.job("build", runs_on: container) do |job|
              job.step("step1", run: Script.new(source: "echo 'Step 1' > /work/step.txt"))
              job.step("step2", run: Script.new(source: "cat /work/step.txt"))
            end
          end
          .to_pipeline
      end

      it_behaves_like "a successful pipeline"

      it "allows steps to share state via the container filesystem" do
        expect(outcomes.last.stdout).to eq("Step 1\n")
      end
    end
  end
end
