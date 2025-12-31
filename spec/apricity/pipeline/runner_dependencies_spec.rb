# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "pipeline with dependencies" do
      let(:pipeline) do
        PipelineBuilder
          .new("dag-ci")
          .action("ci") do |act|
            act.job("test", runs_on: container) do |job|
              job.input("data", :value)
              job.step("test", run: Script.new(source: "echo test"))
            end
            act.job("build", runs_on: container) do |job|
              job.output("data", :value)
              job.step("build", run: Script.new(source: "echo data=ok >> $APRICITY_OUTPUT"))
            end
          end
          .to_pipeline
      end

      it_behaves_like "a successful pipeline"

      it "orders jobs by artifact dependencies, not declaration order" do
        expect(job_order).to eq(%w[build test])
      end
    end
  end
end
