# frozen_string_literal: true

module Apricity
  include Model
  include Model::Builders

  RSpec.describe Pipeline::Runner do
    subject(:runner) { described_class.new(pipeline:) }
    let(:container) { Container.new("ruby", "3.4") }
    let(:outcomes) { runner.run }
    let(:job_order) { outcomes.map(&:job).uniq }

    describe "pipeline with artifacts in matrix jobs" do
      # build -> test(matrix)
      let(:pipeline) do
        PipelineBuilder
          .new("matrix-artifacts-ci")
          .action("ci") do |act|
            act.job("build", runs_on: container) do |job|
              job.output("dist", :artifact)
              job.matrix(shard: [1, 2, 3])
              job.step("write-file", run: Script.new(
                source: <<~SCRIPT
                  set -euo pipefail
                  echo "Creating artifact for shard $MATRIX_SHARD"
                  echo "file for shard $MATRIX_SHARD" > $APRICITY_ARTIFACTS/dist/artifact-shard-$MATRIX_SHARD.txt
                  ls -la $APRICITY_ARTIFACTS/dist
                SCRIPT
              ))
            end

            act.job("check", runs_on: container) do |job|
              job.input("dist", :artifact)
              job.demands("build")
              job.step("read-file", run: Script.new(
                source: <<~SCRIPT
                  set -euo pipefail
                  echo "Contents of artifact directory:"
                  ls -la "$APRICITY_ARTIFACTS"
                  echo "Contents of artifacts/* directory:"
                  ls -la $APRICITY_ARTIFACTS/*
                  echo "Contents of artifacts/*/dist directory:"
                  ls -la $APRICITY_ARTIFACTS/dist/*

                  echo "Reading files:"
                  cat $APRICITY_ARTIFACTS/dist/*/artifact-shard-*.txt
                SCRIPT
              ))
            end
          end
          .to_pipeline
      end

      # it_behaves_like "a successful pipeline"

      it "orders jobs correctly for matrix with artifacts scenario" do
        expect(job_order).to eq(%w[build check])
      end

      it "has expected merged output from each matrix shard" do
        expect(outcomes.last.stdout).to include("file for shard 1\nfile for shard 2\nfile for shard 3\n")
      end
    end
  end
end
