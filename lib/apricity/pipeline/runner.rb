# frozen_string_literal: true

module Apricity
  module Pipeline
    # Executes a pipeline
    # rubocop:disable Metrics/ClassLength
    class Runner
      def initialize(pipeline:, run_instance: nil)
        @pipeline = pipeline
        @run_instance = run_instance || Run::Instance.create(pipeline)
        @outputs_by_node = Hash.new { |h, k| h[k] = {} }

        return if pipeline.is_a?(Model::Pipeline)

        raise ArgumentError, "Expected Pipeline, got #{pipeline.class}"
      end

      def run(&)
        sink = mutex_sink(&)

        nodes = Pipeline::Reducer.lower(@pipeline)
        graph = Pipeline::Graph.new(nodes)
        graph.analyze

        context = JobExecution::PipelineStateContext[pipeline_name, @pipeline.path, {}, {}, {}, graph.dependencies]
        run!(nodes, graph, context:, &sink)
      end

      def mutex_sink(&block)
        user_sink = Apricity::Configuration.instance.output_sink || NullOutputSink.new
        user_sink = block if block_given?
        event_mutex = Mutex.new
        ->(event) { event_mutex.synchronize { user_sink.call(event) } }
      end

      def run!(nodes, graph, context: empty_context, &sink)
        ret = if concurrent?
                run_concurrently(nodes, context:,
                                        sink:)
              else
                run_linear(graph.topological_sort, context:, sink:)
              end
        finish_pipeline(nodes, context:, sink:, ret:)
      end

      def finish_pipeline(nodes, context:, sink:, ret:)
        pipeline_finished = JobExecution::Events::PipelineFinished[pipeline_name:, finished_at: Time.now,
                                                                   outputs_by_node: @outputs_by_node]
        plugins = nodes.flat_map(&:plugins).compact.uniq(&:key)
        plugins.each { |plugin| plugin.handle(pipeline_finished, context:, emitter: sink) }
        sink[pipeline_finished]
        ret
      end

      private

      def concurrent? = false
      def empty_context = JobExecution::PipelineStateContext.empty(pipeline_name, pipeline.path)

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      def run_concurrently(nodes, sink:, context: empty_context)
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
            # if we have any other sentinel, ignore
          end
        end

        Console.debug(self, "pipeline:complete", pipeline_name:, total_outcomes: all_outcomes.size)
        all_outcomes
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def run_linear(nodes, sink:, context: empty_context)
        ret = nodes.flat_map { run_node!(it, context:, sink:).outcomes }
        Console.debug(self, "pipeline:complete", pipeline_name:, total_outcomes: ret.size)
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

      def run_node!(node, sink:, context: empty_context)
        return skip_node(node, context, sink) if skip?(node, context)

        result = run_node(node, env: environment_values(node, context),
                                artifact_inputs: artifact_inputs(node, context),
                                sink:)
        extract_values(node, result, context) if result.passed?
        @outputs_by_node[node.id] = result.outputs
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
        node.inputs.filter_map do |input|
          case input.type
          when :artifact
            # skip
          when :value
            [input.key.upcase, context.value(input.key)]
          else
            raise "Unknown input type #{input.type} for input #{input.key}"
          end
        end.to_h
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
        JobExecution::Orchestrator.new(run: @run_instance, node:, env:, artifact_inputs:, sink:)
                                  .perform
      end

      def pipeline_name = @pipeline.name
    end
    # rubocop:enable Metrics/ClassLength
  end
end
