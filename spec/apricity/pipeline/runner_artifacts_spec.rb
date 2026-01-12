# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "downstream job can read files produced by an upstream job via an artifact directory" do
      let(:pipeline) do
        PipelineBuilder
          .new("artifact-dir-ci")
          .action("ci") do |act|
            act.job("deploy", runs_on: container) do |job|
              job.input("dist", :artifact)
              job.step("deploy", run: Script.new(
                source: "cat $APRICITY_ARTIFACTS/dist/artifact.txt"
              ))
            end

            act.job("build", runs_on: container) do |job|
              job.output("dist", :artifact)
              job.step("build", run: Script.new(
                source: <<~SCRIPT
                  set -euxo pipefail

                  ls -la "$APRICITY_ARTIFACTS" || true
                  ls -la "$APRICITY_ARTIFACTS/dist" || true
                  cat "$APRICITY_ARTIFACTS/dist/artifact.txt" || true
                  mkdir -p "$APRICITY_ARTIFACTS/dist"
                  echo build > "$APRICITY_ARTIFACTS/dist/artifact.txt"
                  ls -la "$APRICITY_ARTIFACTS/dist"
                  cat "$APRICITY_ARTIFACTS/dist/artifact.txt"
                SCRIPT
              ))
            end
          end
          .to_pipeline
      end

      it "allows downstream jobs to read files from upstream jobs' artifact directories" do
        expect(outcomes.last.stdout).to eq("build\n")
      end
    end
  end
end
