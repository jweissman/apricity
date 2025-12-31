# frozen_string_literal: true

# shared examples for apricity pipelines
RSpec.shared_examples "a successful pipeline" do
  let(:pipeline_runner) { Apricity::Pipeline::Runner.new(pipeline:) }
  let(:pipeline_outcomes) { pipeline_runner.run }

  it "has outcomes for all steps" do
    expect(pipeline_outcomes).to all(be_a(Apricity::Model::StepOutcome))
  end

  it "completes all steps successfully" do
    expect(pipeline_outcomes).to all(be_successful)
  end

  it "has an outcome for each step in the pipeline" do
    expect(pipeline_outcomes.size).to eq(pipeline.total_steps)
  end
end
