# frozen_string_literal: true

module Apricity
  module Pipeline
    # Reduces a high-level pipeline definition into executable job nodes
    class Reducer
      # Convert pipeline definition to lower-level Node representation
      def self.lower(pipeline)
        Console.info(self, "Reducing pipeline to job nodes...", total_steps: pipeline.total_steps)
        nodes = []
        pipeline.actions.each do |action|
          action.jobs.each do |job|
            nodes << build_job_node(job, action)
          end
        end
        Console.info(self, "Pipeline reduced", total_steps: pipeline.total_steps, total_nodes: nodes.size)
        nodes
      end

      def self.build_job_node(job, action) = JobExecution::Node.new(
        id: "#{action.name}::#{job.name}",
        runs_on: job.runs_on,
        job_name: job.name, action_name: action.name,
        inputs: job.inputs, outputs: job.outputs,
        conditions: job.conditions, needs: job.needs,
        steps: job.steps,
        mounts: job.mounts, plugins: job.plugins
      )
    end
  end
end
