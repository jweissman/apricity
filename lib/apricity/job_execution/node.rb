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
      :plugins,
      :matrix,
      :env,
      :services
    ) do
      def self.from_model(node_id, action:, job:)
        new(
          id: node_id, runs_on: job.runs_on,
          job_name: job.name, action_name: action.name,
          steps: job.steps,
          inputs: job.inputs, outputs: job.outputs,
          conditions: job.conditions, needs: job.needs,
          mounts: job.mounts, services: job.services,
          plugins: plugins(job, node_id),
          matrix: {}, env: {}
        )
      end

      def self.plugins(job, node_id)
        job.plugins&.map do |model_plugin|
          model_plugin.plugin_class.new(job_id: node_id, options: model_plugin.with)
        end
      end

      def with(**attrs) = self.class.new(**to_h, **attrs)
    end
  end
end
