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

# Apricity: A lightweight CI/CD pipeline runner using Docker containers
#
# Provides pipeline definition, dependency analysis, and job execution
# inside isolated Docker containers.
#
module Apricity
  class Error < StandardError; end
  class JobExecutionError < Error; end

  def self.configure
    yield(Configuration.instance) if block_given?
    true
  end

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
      :mounts
    )

    Context = Data.define(
      :nodes,       # job_id => :success | :failure | :skipped
      :artifacts,   # key => value
      :values,      # key => value,
      :dependencies # job_id => [dependent_job_ids]
    ) do
      def self.empty = Context.new({}, {}, {}, {})
      def artifact(key)        = artifacts[key]
      def value(key)           = values[key]
      def node_status(node_id) = nodes[node_id]
    end

    Result = Data.define(:outcomes, :outputs) do
      def passed? = outcomes.all?(&:successful?)
      def failed? = outcomes.any?(&:failed?)
    end

    module Events
      def self.prefix(event)
        "#{event.node.action_name}##{event.node.job_name}"
      end

      JobStarted = Data.define(:node) do
        def pretty = "started job #{node.job_name}"
      end
      JobSkipped = Data.define(:node, :reason) do
        def pretty = "skipped #{node.job_name} due to #{reason}"
      end
      JobFinished = Data.define(:node, :status) do
        def pretty = "finish job with status #{status}"
      end

      StepStarted = Data.define(:node, :step) do
        def pretty = "started step #{step.name}"
      end
      StepFinished = Data.define(:node, :step, :status) do
        def pretty = "finished step #{step.name}"
      end

      StdoutChunk = Data.define(:node, :step, :chunk) do
        def pretty = "(stdout chunk from step #{step.name})"
      end
      StderrChunk = Data.define(:node, :step, :chunk) do
        def pretty = "(stderr chunk from step #{step.name})"
      end
    end
  end

  class OutputSink
    def initialize; end

    def call(event)
      handle(event.class.name.split("::").last.downcase.to_sym, event)
    end

    protected

    def handle(event)
      raise NotImplementedError, "OutputSink subclasses must implement handle"
    end
  end

  class NullOutputSink < OutputSink
    def handle(_event, _data); end
  end

  class ConsoleOutputSink < OutputSink
    def handle(type, event)
      case type
      when :stdoutchunk, :stderrchunk
        output_stream(type.to_s.start_with?("stdout") ? :stdout : :stderr, event.chunk)
      else
        $stdout.puts(
          "#{Apricity::JobExecution::Events.prefix(event).ljust(24)} | #{event.pretty}"
        )
      end
    end

    def output_stream(stream, data)
      case stream
      when :stdout then $stdout.print data
      when :stderr then $stderr.print data
      else
        raise "Unknown stream #{stream} in LiveOutputSink"
      end
    end
  end

  class JobExecutor
    WORKING_DIR = "/work".freeze
    DEFAULT_READ_TIMEOUT = 300 # seconds
    attr_reader :node, :env, :artifact_inputs, :sink

    def initialize(
      node:, env: {}, artifact_inputs: {},
      sink: Apricity::Configuration.instance.output_sink || NullOutputSink.new
    )
      @node = node
      @env  = env
      @artifact_inputs = artifact_inputs
      @effective_working_dir = WORKING_DIR
      @last_step_executed = nil
      @prelude = <<~SH
        set -euo pipefail
      SH
      @sink = sink
    end

    def perform
      emit(JobExecution::Events::JobStarted[node:])
      bootstrap
      plan
      outcomes = execute
      outputs = collect

      emit(JobExecution::Events::JobFinished[node:, status: :success])
      JobExecution::Result[outcomes:, outputs:]
    rescue JobExecutionError => e
      Console.error(self, "run_step:error", message: e.message, job_name: node.job_name, step_name: step&.name)
      emit(JobExecution::Events::JobFinished[node:, status: :failure])
      JobExecution::Result[outcomes: [failure_outcome(exception: e)], outputs: {}]
    ensure
      container&.delete(force: true)
    end

    protected

    def bootstrap
      configure_docker
      construct_image
    end

    def plan
      bind_mounts = [
        *node.mounts,
        *Apricity::Configuration.instance.bind_mounts
      ].map do |mount|
        case mount.type
        when :bind
          host_path = File.expand_path(mount.source)
          raise "Mount source does not exist: #{host_path}" unless File.exist?(host_path)

          @effective_working_dir = mount.target if mount.source == "."
          "#{host_path}:#{mount.target}:rw"
        else
          raise "Unknown mount type #{mount.type} for mount #{mount.source} -> #{mount.target}"
        end
      end

      env["APRICITY_OUTPUT"] = "/tmp/apricity-values"
      env["APRICITY_ARTIFACTS"] = "#{WORKING_DIR}/artifacts"

      Console.debug(self, "plan:starting", job_name: node.job_name, inputs: node.inputs, outputs: node.outputs)

      artifact_binds = node.inputs
                           .select { |i| i.type == :artifact }
                           .map do |input|
        host_dir = artifact_inputs[input.key]
        raise "Missing artifact #{input.key}" unless host_dir

        "#{host_dir}:#{WORKING_DIR}/artifacts/#{input.key}:ro"
      end

      @artifact_outputs = {}
      node.outputs.select { |o| o.type == :artifact }.each do |output|
        host_dir = Dir.mktmpdir("artifact-#{output.key}-")
        host_dir = File.realpath(host_dir)
        @artifact_outputs[output.key] = host_dir
        artifact_binds << "#{host_dir}:#{WORKING_DIR}/artifacts/#{output.key}"

        @prelude += "\nmkdir -p #{WORKING_DIR}/artifacts/#{output.key}"
      end

      @binds = [
        *artifact_binds,
        *bind_mounts
      ]

      Console.debug(self, "plan:container_config", binds: @binds, env:, image:, job_name: node.job_name)
    end

    # Execute the steps inside a Docker container
    def execute
      outcomes = []
      container.start
      Console.debug(self, "execute:container_started", container_id: container.id, job_name: node.job_name)

      node.steps.each do |step|
        emit(JobExecution::Events::StepStarted[node:, step:])
        step_outcome = execute_step(step)
        emit(JobExecution::Events::StepFinished[node:, step:, status: step_outcome.status])
        Console.info("[#{step_outcome.status.upcase}] #{step_outcome.job} :: #{step_outcome.step}")
        outcomes << step_outcome
      end

      Console.debug(self, "execute:container_complete", container_id: container.id, job_name: node.job_name,
                                                        action_name: node.action_name)

      outcomes
    end

    def execute_step(step)
      @last_step_executed = step
      stdout = +""
      stderr = +""
      script = [@prelude, step.run.lines.join("\n")].join("\n")
      exec_cmd = ["/bin/bash", "-lc", script]
      exec_opts = { "Cmd" => exec_cmd }
      Console.debug(self, "execute:running_step", container_id: container.id, job_name: node.job_name,
                                                  action_name: node.action_name, step_name: step.name,
                                                  exec_cmd:)
      exec_result = container.exec(
        exec_opts["Cmd"],
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "WorkingDir" => @effective_working_dir,
        "Tty" => false
      ) do |stream, chunk|
        case stream
        when :stdout
          # @sink.stdout(chunk)
          emit(JobExecution::Events::StdoutChunk[node:, step:, chunk:])
          stdout << chunk
        when :stderr
          # @sink.stderr(chunk)
          emit(JobExecution::Events::StderrChunk[node:, step:, chunk:])
          stderr << chunk
        end
      end
      exit_code = exec_result[2]
      raise JobExecutionError, "Step #{step.name} failed with exit code #{exit_code}" unless exit_code.zero?

      Console.debug(self, "execute:step_complete", container_id: container.id, job_name: node.job_name,
                                                   action_name: node.action_name, step_name: step.name,
                                                   stdout_size: stdout.size, stderr_size: stderr.size)
      success_outcome(stdout:, stderr:)
    end

    # Collect outputs after execution
    # - Values are read from a designated file inside the container
    # - Artifacts are container-local during execution and exported explicitly at collect time
    # Returns a hash of output key => value or host directory
    def collect
      output_elements = {}

      values_contents, _err, code = exec_stdout(%(cat "$APRICITY_OUTPUT" 2>/dev/null || true))
      if code.zero? && !values_contents.empty?
        values_contents.each_line do |line|
          key, value = line.strip.split("=", 2)
          output_elements[key] = value if key && value
        end
      end

      @artifact_outputs.each do |key, host_dir|
        container_dir = "#{WORKING_DIR}/artifacts/#{key}"
        pull_artifact_from_container(container_dir, host_dir)
      end

      all_outputs_present = node.outputs.all? do |output|
        if output.type == :value
          output_elements.key?(output.key)
        elsif output.type == :artifact
          Dir.exist?(@artifact_outputs[output.key]) &&
            !Dir.empty?(@artifact_outputs[output.key])
        else
          raise JobExecutionError, "Unknown output type #{output.type} for output #{output.key}"
        end
      end

      unless all_outputs_present
        missing = node.outputs.reject do |output|
          case output.type
          when :value
            output_elements.key?(output.key)
          when :artifact
            Dir.exist?(@artifact_outputs[output.key]) &&
              !Dir.empty?(@artifact_outputs[output.key])
          else
            false
          end
        end
        missing.map! { "'#{it.key}'" }
        message = if missing.length == 1
                    "Declared output #{missing.join} was not produced"
                  else
                    "Declared outputs #{missing.join(", ")} were not produced"
                  end
        message += " for step :#{step.name} in job :#{node.job_name} of action :#{node.action_name}"
        Console.warn(self, "collect:missing_outputs",
                     message:,
                     missing:,
                     node_id: node.id, job_name: node.job_name,
                     action_name: node.action_name, step_name: step.name)
        raise JobExecutionError, message
      end
      output_elements.merge(@artifact_outputs)
    end

    private

    def emit(event) = @sink&.call(event)

    def pull_artifact_from_container(container_dir, host_dir)
      FileUtils.mkdir_p(host_dir)

      tar_data, _err, code = exec_stdout(
        %(cd "#{container_dir}" 2>/dev/null && tar -cf - .)
      )

      return if code != 0 || tar_data.empty?

      Gem::Package::TarReader.new(StringIO.new(tar_data)) do |tar|
        tar.each do |entry|
          dest = File.join(host_dir, entry.full_name)
          if entry.directory?
            FileUtils.mkdir_p(dest)
          else
            FileUtils.mkdir_p(File.dirname(dest))
            File.binwrite(dest, entry.read)
          end
        end
      end
    end

    def exec_stdout(cmd)
      out = +""
      err = +""
      result = container.exec(
        ["/bin/sh", "-lc", cmd],
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "WorkingDir" => @effective_working_dir,
        "Tty" => false
      ) do |stream, chunk|
        stream == :stdout ? out << chunk : err << chunk
      end
      [out, err, result[2]]
    end

    def step = @last_step_executed

    def configure_docker = Docker.options[:read_timeout] = DEFAULT_READ_TIMEOUT
    def construct_image = Docker::Image.create("fromImage" => image)

    def container
      @container ||= Docker::Container.create(
        "Image" => image,
        "AttachStdout" => true, "AttachStderr" => true, "Tty" => false,
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "HostConfig" => { "Binds" => @binds },
        "WorkingDir" => @effective_working_dir,
        "Cmd" => ["/bin/sh", "-lc", "while true; do sleep 3600; done"]
      )
    end

    def failure_outcome(exception:) = Model::StepOutcome.failure(
      node, step, stdout: "", stderr: "", exception:
    )

    def success_outcome(stdout:, stderr:) = Model::StepOutcome.success(
      node, step, stdout:, stderr:
    )

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
      ordered_nodes = graph.topological_sort
      context = JobExecution::Context[{}, {}, {}, graph.dependencies]

      t0 = Time.now
      outcomes = run(ordered_nodes, context:, sink:)
      t1 = Time.now
      Console.info(self, "run:complete", pipeline_name: pipeline.name,
                                         duration_seconds: (t1 - t0).round(2), total_outcomes: outcomes.size)

      outcomes
    end

    def skip_reason(node, context)
      upstream = context.dependencies[node.id] || []
      return :upstream_failure if upstream.any? { |id| context.nodes[id] != :success }

      return :conditions_unmet unless verify_conditions(node, context)

      return :missing_artifact_input if node.inputs
                                            .select { |i| i.type == :artifact }
                                            .to_h { |i| [i.key, context.artifacts[i.key]] }
                                            .any? { |_, v| v.nil? }

      nil
    end

    def run_node!(node, sink:, context: ExecutionContext.empty)
      if (reason = skip_reason(node, context))
        context.nodes[node.id] = :skipped
        outcomes = [Model::StepOutcome.skipped(node, node.steps.first, reason:)]
        return JobExecution::Result[outcomes:, outputs: {}]
      end

      env = {}
      artifact_inputs = node.inputs
                            .select { |i| i.type == :artifact }
                            .to_h { |i| [i.key, context.artifacts[i.key]] }

      Console.debug(self, "run_node:starting", job_name: node.job_name, inputs: node.inputs, outputs: node.outputs)
      node.inputs.each do |input|
        case input.type
        when :artifact
          # skip?
        when :value
          env[input.key.upcase] = context.value(input.key)
        else
          raise "Unknown input type #{input.type} for input #{input.key}"
        end
      end
      result = run_node(node, env:, artifact_inputs:, sink:)
      extract_values!(node, result, context) if result.passed?

      # Record node status
      status = result.passed? ? :success : :failure
      context.nodes[node.id] = status

      result
    end

    private

    def extract_values!(node, result, context)
      node.outputs.each do |output|
        case output.type
        when :value
          context.values[output.key] = extract_value(result.outputs, output.key)
        when :artifact
          context.artifacts[output.key] = extract_value(result.outputs, output.key)
        else
          raise "Unknown output type #{output.type} for output #{output.key}"
        end
      end
    end

    def run(
      nodes, sink:, context: ExecutionContext.empty
    ) = nodes.flat_map { run_node!(it, context:, sink:).outcomes }

    def extract_value(outputs, key) = (outputs[key] if outputs.key?(key))

    def verify_conditions(node, context)
      node.conditions.none? || node.conditions.all? { it.evaluate(context) }
    end

    def run_node(node, sink:, env: {}, artifact_inputs: {}) = JobExecutor.new(
      node:, env:, artifact_inputs:, sink:
    ).perform
  end
end
