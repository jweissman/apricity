# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "fan-out/fan-in pipeline" do
      # build -> test1
      #       -> test2
      # test1 + test2 -> deploy
      let(:pipeline) do
        PipelineBuilder
          .new("fanout-ci")
          .action("ci") do |act|
            act.job("deploy", runs_on: container) do |job|
              job.input("test1_result", :value)
              job.input("test2_result", :value)
              job.step("deploy", run: Script.new(source: "echo deploy"))
            end

            act.job("test1", runs_on: container) do |job|
              job.input("dist", :artifact)
              job.output("test1_result", :value)
              job.step("test1", run: Script.new(source: "echo test1_result=ok >> $APRICITY_OUTPUT"))
            end

            act.job("test2", runs_on: container) do |job|
              job.input("dist", :artifact)
              job.input("test1_result", :value)
              job.output("test2_result", :value)
              job.step("test2", run: Script.new(source: "echo test2_result=ok >> $APRICITY_OUTPUT"))
            end

            act.job("build", runs_on: container) do |job|
              job.output("dist", :artifact)
              job.step("build", run: Script.new(source:
                                                  "mkdir -p dist \n" \
                                                  "echo build > $APRICITY_ARTIFACTS/dist/artifact.txt"))
            end
          end
          .to_pipeline
      end

      it_behaves_like "a successful pipeline"

      it "orders jobs correctly for fan-out/fan-in scenario" do
        expect(job_order).to eq(%w[build test1 test2 deploy])
      end
    end
  end
end
