# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "echo pipeline" do
      let(:command) { Script.new(source: "echo 'Hello, Apricity!'") }
      let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

      it_behaves_like "a successful pipeline"

      it "captures simple echo output" do
        expect(outcomes.first.stdout).to eq("Hello, Apricity!\n")
      end
    end
  end
end
