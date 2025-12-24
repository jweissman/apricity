# frozen_string_literal: true

module Apricity
  # Executes a pipeline
  # rubocop:disable Metrics/ClassLength
  class PipelineRunner
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

            # Run your existing skip logic (emits JobSkipped + updates context.nodes)
            result = run_node.call(node, sink:, context:) # this will go through run_node! and skip
            results << [node_id, result]
            next
          end

          # deps succeeded => run concurrently
          pending.delete(node_id)
          progressed = true

          running[node_id] = Thread.new do
            result = run_node.call(node, sink:, context:)
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

    attr_reader :pipeline

    def initialize(pipeline)
      @pipeline = pipeline
    end

    # rubocop:disable Metrics/AbcSize
    def run!(&block)
      user_sink = Apricity::Configuration.instance.output_sink || NullOutputSink.new
      user_sink = block if block_given?
      event_mutex = Mutex.new
      sink = ->(event) { event_mutex.synchronize { user_sink.call(event) } }

      nodes = PipelineReducer.lower(pipeline)
      graph = PipelineGraph.new(nodes)
      graph.analyze

      context = JobExecution::Context[{}, {}, {}, graph.dependencies]
      # run(graph.topological_sort, context:, sink:)
      run_concurrently(nodes, context:, sink:)
    end
    # rubocop:enable Metrics/AbcSize

    private

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/AbcSize
    def run_concurrently(nodes, sink:, context: ExecutionContext.empty)
      dependencies = context.dependencies
      node_by_id = nodes.to_h { |n| [n.id, n] }
      pending = nodes.to_set(&:id)
      running = {}
      completed = {}
      results = Queue.new
      all_outcomes = []
      while pending.any? || running.any?
        status = Scheduler.execute(
          pending:, running:, completed:, dependencies:,
          node_by_id:, sink:, context:, results:, run_node: method(:run_node!)
        )

        case status
        when :deadlock
          raise "Scheduler deadlock: pending=#{pending.to_a.inspect} running=#{running.keys.inspect} \
            completed=#{completed.inspect}"
        when :launched
          # nothing to do, just continue

        when :wait
          node_id, result = results.pop # BLOCK until one finishes
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
          all_outcomes.concat(result.outcomes)
        when Array
          _tag, _node_id, result = status
          all_outcomes.concat(result.outcomes)
          # else
          # if you keep any other sentinel, ignore
        end
      end

      Console.debug(self, "pipeline:complete", pipeline_name:, total_outcomes: all_outcomes.size)
      all_outcomes
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def run(nodes, sink:, context: ExecutionContext.empty)
      ret = nodes.flat_map { run_node!(it, context:, sink:).outcomes }
      Console.debug(self, "pipeline:complete", pipeline_name: pipeline.name, total_outcomes: ret.size)
      ret
    end

    def upstream_failures?(node, context)
      upstream = context.dependencies[node.id] || []
      upstream.any? { |id| context.nodes[id] != :success }
    end

    def skip_reason(node, context)
      return :upstream_failure if upstream_failures?(node, context)
      return :conditions_unmet unless verify_conditions(node, context)
      return :missing_artifact_input if node.inputs
                                            .select { |i| i.type == :artifact }
                                            .to_h { |i| [i.key, context.artifacts[i.key]] }
                                            .values.any?(&:nil?)

      nil
    end

    def skip?(node, context) = skip_reason(node, context)

    def skip_node(node, context, sink)
      reason = skip_reason(node, context)
      context.nodes[node.id] = :skipped
      sink&.call(JobExecution::Events::JobSkipped[node:, reason:, skipped_at: Time.now])
      JobExecution::Result[
        outcomes: [Model::StepOutcome.skipped(node, node.steps.first, reason:)],
        outputs: {}
      ]
    end

    def run_node!(node, sink:, context: ExecutionContext.empty)
      return skip_node(node, context, sink) if skip?(node, context)

      result = run_node(node, env: environment_values(node, context),
                              artifact_inputs: artifact_inputs(node, context),
                              sink:)
      extract_values(node, result, context) if result.passed?
      status = result.passed? ? :success : :failure
      context.nodes[node.id] = status
      result
    end

    def artifact_inputs(node, context)
      node.inputs
          .select { |i| i.type == :artifact }
          .to_h { |i| [i.key, context.artifacts[i.key]] }
    end

    def environment_values(node, context)
      node.inputs.map do |input|
        case input.type
        when :artifact
          # skip
        when :value
          [input.key.upcase, context.value(input.key)]
        else
          raise "Unknown input type #{input.type} for input #{input.key}"
        end
      end.compact.to_h
    end

    def extract_values(node, result, context) = node.outputs.each { extract_value!(it, result, context) }

    def extract_value!(output, result, context)
      case output.type
      when :value
        context.values[output.key] = extract_value(result.outputs, output.key)
      when :artifact
        context.artifacts[output.key] = extract_value(result.outputs, output.key)
      else
        raise "Unknown output type #{output.type} for output #{output.key}"
      end
    end

    def extract_value(outputs, key) = (outputs[key] if outputs.key?(key))

    def verify_conditions(node, context)
      node.conditions.none? || node.conditions.all? { it.evaluate?(context) }
    end

    def run_node(node, sink:, env: {}, artifact_inputs: {})
      JobExecution::Orchestrator.new(node:, env:, artifact_inputs:, sink:).perform
    end

    def pipeline_name = pipeline.name
  end
  # rubocop:enable Metrics/ClassLength
end
