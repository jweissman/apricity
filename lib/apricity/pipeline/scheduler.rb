# frozen_string_literal: true

module Apricity
  module Pipeline
    # Simple job scheduler for running jobs with dependencies
    class Scheduler
      def self.deps(node_id, dependencies) = dependencies[node_id] || []

      def self.deps_completed?(node_id, dependencies, completed)
        deps(node_id, dependencies).all? { |dep_id| completed.key?(dep_id) }
      end

      def self.deps_succeeded?(node_id, dependencies, completed)
        deps(node_id, dependencies).all? { |dep_id| completed[dep_id] == :success }
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/ParameterLists
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      def self.execute(pending:, running:, completed:, dependencies:, node_by_id:, sink:, context:, results:,
                       run_node:)
        max_concurrency = 4
        progressed = false

        pending.to_a.each do |node_id|
          break if running.size >= max_concurrency

          # Can't decide anything until deps are done
          next unless deps_completed?(node_id, dependencies, completed)

          node = node_by_id.fetch(node_id)

          # If deps are done but not all success => SKIP (don’t deadlock)
          unless deps_succeeded?(node_id, dependencies, completed)
            pending.delete(node_id)
            progressed = true

            # Run skip logic (emits JobSkipped + updates context.nodes)
            result = run_node.call(node, sink:, context:) # this will go through run_node! and skip
            results << [node_id, result]
            next
          end

          # deps succeeded => run concurrently
          pending.delete(node_id)
          progressed = true

          running[node_id] = Thread.new do
            result = begin
              run_node.call(node, sink:, context:)
            rescue StandardError => e
              Console.error(self, "Scheduler: Error running node #{node_id}: #{e.message}", e.backtrace.join("\n"))
              JobExecution::Result[outcomes: [Model::StepOutcome.failure(node, node.steps.first,
                                                                         stdout: "", stderr: "",
                                                                         exception: e)], outputs: {}]
            end
            results << [node_id, result]
          end
        end

        begin
          node_id, result = results.pop(true) # nonblocking
        rescue ThreadError
          node_id = result = nil
        end

        if node_id
          running.delete(node_id)&.join

          status =
            if result.outcomes.all? { |o| o.status.to_sym == :skipped }
              :skipped
            elsif result.passed?
              :success
            else
              :failure
            end

          completed[node_id] = status
          return [:completed, node_id, result]
        end

        # Nothing finished yet
        return :launched if progressed
        return :deadlock if !progressed && running.empty?

        # If we launched something but nothing completed yet, tell caller to wait.
        return :wait if running.any?

        :launched
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/ParameterLists
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize
    end
  end
end
