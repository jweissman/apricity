# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "simple pipeline" do
      let(:command) { Script.new(source: "ruby -e 'puts \"Hello, World!\"'") }
      let(:pipeline) { PipelineBuilder.single_command(container:, command:) }

      it_behaves_like "a successful pipeline"

      it "uses the correct container name" do
        expect(outcomes.first.container.name).to eq("ruby")
      end

      it "uses the correct container version" do
        expect(outcomes.first.container.version).to eq("3.4")
      end

      it "has expected script" do
        expect(outcomes.first.script).to eq("ruby -e 'puts \"Hello, World!\"'")
      end

      it "executes scripts in the given container" do
        expect(outcomes.first.stdout).to eq("Hello, World!\n")
      end
    end
  end
end
