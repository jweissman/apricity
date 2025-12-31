# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "failing pipeline" do
      let(:command) { Script.new(source: "exit 1") }
      let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

      it "captures failure of a command" do
        expect(outcomes.first).to be_failed
      end

      it "reports the failure in the outcome message" do
        expect(outcomes.first.message).to include("Step execute failed")
      end
    end
  end
end
