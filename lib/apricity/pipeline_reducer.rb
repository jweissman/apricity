# frozen_string_literal: true

module Apricity
  # Reduces a high-level pipeline definition into executable job nodes
  class PipelineReducer
    # Convert pipeline definition to lower-level Node representation
    def self.lower(pipeline)
      nodes = []
      pipeline.actions.each do |action|
        action.jobs.each do |job|
          nodes << build_job_node(job, action)
        end
      end
      nodes
    end

    def self.build_job_node(job, action) = JobExecution::Node.new(
      id: SecureRandom.uuid,
      inputs: job.inputs, outputs: job.outputs,
      conditions: job.conditions, needs: job.needs,
      runs_on: job.runs_on,
      steps: job.steps,
      job_name: job.name,
      action_name: action.name,
      mounts: job.mounts
    )
  end
end
