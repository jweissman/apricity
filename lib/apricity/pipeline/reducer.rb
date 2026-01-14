# frozen_string_literal: true

module Apricity
  module Pipeline
    # Reduces a high-level pipeline definition into executable job nodes
    # -- maybe call this 'lowerer' to deconflict with 'reducer' in evented map-reduce sense?
    class Reducer
      # Convert pipeline definition to lower-level Node representation
      def self.lower(pipeline)
        # Console.info(self, "Reducing pipeline to job nodes...", total_steps: pipeline.total_steps)
        nodes = []
        pipeline.actions.each do |action|
          nodes.concat(build_action_nodes(action))
        end
        # Console.info(self, "Pipeline reduced", total_steps: pipeline.total_steps, total_nodes: nodes.size)
        nodes
      end

      # rubocop:disable Metrics/MethodLength
      def self.build_action_nodes(action)
        nodes = []
        action.jobs.each do |job|
          if job.strategy&.matrix&.any?
            combos = expand_matrix(job)
            total = combos.size
            combos.each do |matrix_vars|
              nodes << build_job_node(job, action, matrix_vars, total:)
            end
          else
            nodes << build_job_node(job, action, {})
          end
        end
        nodes
      end
      # rubocop:enable Metrics/MethodLength

      def self.build_job_node(job, action, matrix_vars, total: 0)
        base = JobExecution::Node.from_model("#{action.name}::#{job.name}", action:, job:)
        if matrix_vars.any?
          base.with(
            id: "#{base.id}[#{matrix_vars.map { |k, v| "#{k}=#{v}" }.join(",")}]",
            env: base.env.merge(matrix_env(matrix_vars, total:)),
            matrix: matrix_vars
          )
        else
          base
        end
      end

      def self.matrix_env(vars, total:)
        {
          "MATRIX_TOTAL" => total.to_s
        }.merge(
          vars.transform_keys { |k| "MATRIX_#{k.upcase}" }
              .transform_values(&:to_s)
        )
      end

      def self.expand_matrix(job)
        keys = job.strategy.matrix.keys
        values = job.strategy.matrix.values

        values
          .first
          .product(*values.drop(1))
          .map { |combo| keys.zip(combo).to_h }
      end
    end
  end
end
