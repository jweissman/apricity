# frozen_string_literal: true

module Apricity
  module JobExecution
    Node = Data.define(
      :id,
      :runs_on,
      :steps,        # [Step] or just step scripts
      :inputs,       # [Input]
      :outputs,      # [Output]
      :conditions,   # [Conditions::*]
      :needs,
      :job_name,
      :action_name,
      :mounts,
      :plugins
    ) do
      def self.from_model(node_id, action:, job:)
        new(
          id: node_id, runs_on: job.runs_on,
          job_name: job.name, action_name: action.name,
          steps: job.steps,
          inputs: job.inputs, outputs: job.outputs,
          conditions: job.conditions, needs: job.needs,
          mounts: job.mounts,
          plugins: job.plugins
        )
      end
    end
  end
end
