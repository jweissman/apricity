# frozen_string_literal: false

require "console"
require "securerandom"
require "base64"
require "docker-api"
require "rubygems/package"
require "stringio"

require_relative "apricity/version"
require_relative "apricity/configuration"
require_relative "apricity/model"
require_relative "apricity/pipeline_graph"
require_relative "apricity/pipeline_reducer"
require_relative "apricity/conditions"
require_relative "apricity/job_execution"

# Apricity: A lightweight CI/CD pipeline runner using Docker containers
#
# Provides pipeline definition, dependency analysis, and job execution
# inside isolated containers.
#
module Apricity
  class Error < StandardError; end
  class JobExecutionError < Error; end

  def self.configure
    yield(Configuration.instance) if block_given?
  end

  # Base class for output sinks
  class OutputSink
    def call(event) = handle(event.type, event)

    protected

    def handle(type, data)
      raise NotImplementedError, "OutputSink subclasses must implement handle"
    end
  end

  # A no-op output sink that discards all events
  class NullOutputSink < OutputSink
    def handle(_type, _data); end
  end

  # Executes a single job inside a Docker container
  class JobExecutor
    DEFAULT_READ_TIMEOUT = 300 # seconds
    attr_reader :node, :env, :artifact_inputs, :sink

    def initialize(
      node:, env: {}, artifact_inputs: {},
      sink: Apricity::Configuration.instance.output_sink || NullOutputSink.new
    )
      @node = node
      @env  = env
      @artifact_inputs = artifact_inputs
      @effective_working_dir = JobExecution::WORKING_DIR
      @last_step_executed = nil
      @prelude = <<~SH
        set -euo pipefail
      SH
      @sink = sink
    end

    def perform
      emit(JobExecution::Events::JobStarted[node:])
      run_job
    rescue JobExecutionError => e
      handle_failure(e)
    ensure
      container&.delete(force: true)
    end

    protected

    def run_job
      bootstrap
      plan
      outcomes = execute
      outputs = collect

      emit(JobExecution::Events::JobFinished[node:, status: :success])
      JobExecution::Result[outcomes:, outputs:]
    end

    def handle_failure(exception)
      Console.error(self, "run_step:error", message: exception.message, job_name: node.job_name, step_name: step&.name)
      emit(JobExecution::Events::JobFinished[node:, status: :failure])
      JobExecution::Result[outcomes: [failure_outcome(exception:)], outputs: {}]
    end

    def bootstrap
      configure_docker
      construct_image
    end

    def planner = @planner ||= JobExecution::Planner.new(node:, env:, artifact_inputs:, config: Apricity::Configuration.instance)

    def plan
      planner.call
      @binds            = planner.binds
      @artifact_outputs = planner.artifact_outputs
      @effective_working_dir = planner.effective_working_dir
      @prelude += planner.prelude
    end

    # Execute the steps inside a Docker container
    def execute
      container.start
      node.steps.map do |step|
        emit(JobExecution::Events::StepStarted[node:, step:])
        @last_step_executed = step
        step_outcome = execute_step(step)
        emit(JobExecution::Events::StepFinished[node:, step:, status: step_outcome.status])
        step_outcome
      end
    end

    def execute_step(step)
      stdout, stderr = JobExecution::StepExecutor.new(
        step:, env:, sink:, node:
      ).perform(
        prelude: @prelude,
        container:,
        emit: ->(event) { emit(event) },
        container_options: common_container_options
      )
      success_outcome(stdout:, stderr:)
    end

    # Returns a hash of output key => value or host directory
    def collect = JobExecution::Collector.new(node:, container:, artifact_outputs: @artifact_outputs).collect

    private

    def emit(event) = @sink&.call(event)
    def step = @last_step_executed
    def configure_docker = Docker.options[:read_timeout] = DEFAULT_READ_TIMEOUT
    def construct_image = Docker::Image.create("fromImage" => image)

    def common_container_options
      {
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "WorkingDir" => @effective_working_dir,
        "Tty" => false
      }
    end

    def container
      @container ||= Docker::Container.create(
        "Image" => image,
        "AttachStdout" => true, "AttachStderr" => true,
        "HostConfig" => { "Binds" => @binds },
        "Cmd" => ["/bin/sh", "-lc", "while true; do sleep 3600; done"],
        **common_container_options
      )
    end

    def failure_outcome(exception:)
      Model::StepOutcome.failure(node, step, stdout: "", stderr: "", exception:)
    end

    def success_outcome(stdout:, stderr:) = Model::StepOutcome.success(node, step, stdout:, stderr:)
    def image = "#{node.runs_on.name}:#{node.runs_on.version}"
  end

  # Executes a pipeline
  class PipelineRunner
    attr_reader :pipeline

    def initialize(pipeline)
      @pipeline = pipeline
    end

    def pipeline_name = pipeline.name

    def run!(&block)
      sink = Apricity::Configuration.instance.output_sink || NullOutputSink.new
      sink = block if block_given?
      nodes = PipelineReducer.lower(pipeline)
      graph = PipelineGraph.new(nodes)
      context = JobExecution::Context[{}, {}, {}, graph.dependencies]
      run(graph.topological_sort, context:, sink:)
    end

    private

    def run(
      nodes, sink:, context: ExecutionContext.empty
    )
      t0 = Time.now
      ret = nodes.flat_map { run_node!(it, context:, sink:).outcomes }
      t1 = Time.now
      Console.debug(self, "run:complete", pipeline_name: pipeline.name,
                                          duration_seconds: (t1 - t0).round(2), total_outcomes: ret.size)
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
                                            .any? { |_, v| v.nil? }

      nil
    end

    def skip?(node, context)
      skip_reason(node, context)
    end

    def skip_node(node, context, sink)
      reason = skip_reason(node, context)
      context.nodes[node.id] = :skipped
      sink&.call(JobExecution::Events::JobSkipped[node:, reason:])
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

    def extract_values(node, result, context)
      node.outputs.each do |output|
        extract_value!(output, result, context)
      end
    end

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
      JobExecutor.new(
        node:, env:, artifact_inputs:, sink:
      ).perform
    end
  end
end
