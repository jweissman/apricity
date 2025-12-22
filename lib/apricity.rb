# frozen_string_literal: true

require "console"
require "securerandom"
require "base64"
require "docker-api"

require_relative "apricity/version"
require_relative "apricity/model"
require_relative "apricity/pipeline_graph"

module Apricity
  class Error < StandardError; end
  class StepExecutionError < Error; end

  # class Configuration; end
  # def self.configure = yield(Configuration)

  Artifact = Data.define(:name)
  Value    = Data.define(:name)

  JobNode = Data.define(
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

  ExecutionContext = Data.define(
    :nodes,       # job_id => :success | :failure | :skipped
    :artifacts,   # key => value
    :values,      # key => value,
    :dependencies # job_id => [dependent_job_ids]
  ) do
    def self.empty = ExecutionContext.new({}, {}, {}, {})
    def artifact(key)        = artifacts[key]
    def value(key)           = values[key]
    def node_status(node_id) = nodes[node_id]
  end

  # Models for conditions and their evaluation
  module Conditions
    Success = Data.define(:node_id) do
      def to_s = "Success(#{node_id})"
      def evaluate(context) = context.node_status(node_id) == :success
    end
    Equals = Data.define(:key, :value) do
      def to_s = "Equals(#{key} == #{value})"
      def evaluate(context) = context.value(key) == value
    end
    Exists = Data.define(:artifact_key) do
      def to_s = "Exists(#{artifact_key})"
      def evaluate(context) = !context.artifact(artifact_key).nil?
    end
    All = Data.define(:conds) do
      def to_s = "All(#{conds.map(&:to_s).join(", ")})"
      def evaluate(context) = conds.all? { |c| c.evaluate(context) }
    end
    Any = Data.define(:conds) do
      def to_s = "Any(#{conds.map(&:to_s).join(", ")})"
      def evaluate(context) = conds.any? { |c| c.evaluate(context) }
    end

    # Evaluate a condition against the given execution context
    def self.evaluate(cond, context)
      ret = cond.evaluate(context)
      Console.info(self, "evaluate_condition", condition: cond.to_s, context:, result: ret)
      ret
    end
  end

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

    def self.build_job_node(job, action) = JobNode.new(
      id: SecureRandom.uuid,
      runs_on: job.runs_on,
      steps: job.steps,
      inputs: job.inputs,
      outputs: job.outputs,
      conditions: job.conditions,
      needs: job.needs,
      job_name: job.name,
      action_name: action.name,
      mounts: job.mounts
    )
  end

  # Executes a single step inside a container
  class StepExecutor
    WORKING_DIR = "/work"
    DEFAULT_READ_TIMEOUT = 300 # seconds
    attr_reader :step, :node, :env, :artifact_inputs

    def initialize(step:, node:, env: {}, artifact_inputs: {})
      @step = step
      @node = node
      @env  = env
      @artifact_inputs = artifact_inputs
    end

    def perform
      configure_docker
      construct_image
      plan
      stdout, stderr = execute
      outputs = collect
      success_event(stdout, stderr, outputs:)
    rescue StepExecutionError => e
      Console.error(self, "run_step:error", e)
      failure_event(stdout, stderr, exception: e)
    ensure
      FileUtils.remove_entry(@output_dir)
      container&.delete(force: true)
    end

    protected

    def plan
      @output_dir = Dir.mktmpdir("apricity-outputs")
      env["APRICITY_OUTPUT"] = "/apricity/outputs/values.txt"
      env["APRICITY_ARTIFACTS"] = "#{WORKING_DIR}/artifacts"

      Console.debug(self, "run_step:starting", job_name: node.job_name, inputs: node.inputs, outputs: node.outputs,
                                               step_name: step.name)

      artifact_binds = node.inputs
                           .select { |i| i.type == :artifact }
                           .map do |input|
        host_dir = artifact_inputs[input.key]
        raise "Missing artifact #{input.key}" unless host_dir

        "#{host_dir}:#{WORKING_DIR}/artifacts/#{input.key}:ro"
      end

      @artifact_outputs = {}
      node.outputs.select { |o| o.type == :artifact }.each do |output|
        host_dir = Dir.mktmpdir("apricity-artifact-#{output.key}") # but the job just produces to that dir name directly
        @artifact_outputs[output.key] = host_dir
        artifact_binds << "#{host_dir}:#{WORKING_DIR}/artifacts/#{output.key}"
      end

      mount_binds = node.mounts.map do |mount|
        case mount.type
        when :bind
          host_path = File.expand_path(mount.source)
          raise "Mount source does not exist: #{host_path}" unless File.exist?(host_path)

          "#{host_path}:#{mount.target}:rw"
        else
          raise "Unknown mount type #{mount.type} for mount #{mount.source} -> #{mount.target}"
        end
      end

      @binds = ["#{@output_dir}:/apricity/outputs", *artifact_binds, *mount_binds]
      @binds.each do |b|
        src = b.split(":", 2).first
        next if src.start_with?("/") && File.exist?(src) # rough check
      end
      Console.debug(self, "run_step:container_config", binds: @binds, env:, image:, cmd:, job_name: node.job_name)
    end

    # Execute the step inside a Docker container
    def execute
      stdout = +""
      stderr = +""

      Console.debug(self, "run_step:container_setup", container_id: container.id, job_name: node.job_name,
                                                      action_name: node.action_name, step_name: step.name)

      reader = Thread.new do
        container.attach(stream: true, stdout: true, stderr: true) do |stream, chunk|
          case stream
          when :stdout
            $stdout.print chunk
            stdout << chunk
          when :stderr
            $stderr.print chunk
            stderr << chunk
          end
        end
      end

      container.start
      container.wait

      reader.join

      Console.debug(self, "run_step:container_complete", container_id: container.id, job_name: node.job_name,
                                                         action_name: node.action_name, step_name: step.name,
                                                         stdout_size: stdout.size, stderr_size: stderr.size)

      [stdout, stderr]
    end

    def collect
      output_elements = {}

      values_file = File.join(@output_dir, "values.txt")
      if File.exist?(values_file)
        File.readlines(values_file).each do |line|
          key, value = line.strip.split("=", 2)
          output_elements[key] = value if key && value
        end
      end

      all_outputs_present = node.outputs.all? do |output|
        if output.type == :value
          output_elements.key?(output.key)
        elsif output.type == :artifact
          Dir.exist?(@artifact_outputs[output.key]) &&
            !Dir.empty?(@artifact_outputs[output.key])
        else
          raise StepExecutionError, "Unknown output type #{output.type} for output #{output.key}"
        end
      end

      unless all_outputs_present
        # missing = node.outputs.reject { |o| output_elements.key?(o.key) }
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
        message = if missing.length == 1
                    "Declared output #{missing.map { "'#{it.key}'" }.join(", ")} was not produced"
                  else
                    "Declared outputs #{missing.map { "'#{it.key}'" }.join(", ")} were not produced"
                  end
        message += " for step :#{step.name} in job :#{node.job_name} of action :#{node.action_name}"
        Console.warn(self, "run_step:missing_outputs",
                     message:,
                     missing:,
                     node_id: node.id, job_name: node.job_name,
                     action_name: node.action_name, step_name: step.name)
        raise StepExecutionError, message
      end
      output_elements.merge(@artifact_outputs)
    end

    private

    def configure_docker = Docker.options[:read_timeout] = DEFAULT_READ_TIMEOUT
    def construct_image = Docker::Image.create("fromImage" => image)

    def container
      @container ||= Docker::Container.create(
        "Image" => image,
        "Cmd" => cmd,
        "AttachStdout" => true,
        "AttachStderr" => true,
        "Tty" => false,
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "HostConfig" => {
          "Binds" => @binds
        },
        "WorkingDir" => WORKING_DIR
      )
    end

    def failure_event(stdout, stderr, exception:) = Model::Event.failure(
      node, step, stdout:, stderr:, exception:
    )

    def success_event(stdout, stderr, outputs: {}) = Model::Event.success(node, step, stdout:, stderr:, outputs:)

    def image = "#{node.runs_on.name}:#{node.runs_on.version}"
    def cmd = ["/bin/sh", "-lc", step.run.lines.join("\n")]
  end

  # Executes a pipeline
  class PipelineRunner
    attr_reader :pipeline

    def initialize(pipeline)
      @pipeline = pipeline
    end

    def pipeline_name = pipeline.name

    def self.lower(pipeline) = PipelineReducer.lower(pipeline)
    # def self.sorted(nodes) = PipelineGraph.new(nodes).topological_sort

    def run!
      nodes = self.class.lower(pipeline)
      graph = PipelineGraph.new(nodes)
      ordered_nodes = graph.topological_sort
      context = ExecutionContext[{}, {}, {}, graph.dependencies]
      run(ordered_nodes, context:)
    end

    def run_node!(node, context: ExecutionContext.empty)
      upstream = context.dependencies[node.id] || []
      if upstream.any? { |id| context.nodes[id] != :success }
        context.nodes[node.id] = :skipped
        return [Model::Event.skipped(node, node.steps.first, reason: "Upstream job failure")]
      end

      unless verify_conditions(node, context)
        return [
          Model::Event.skipped(node, node.steps.first, reason: "Conditions not met")
        ]
      end

      events = []
      env = {}
      artifact_inputs = node.inputs
                            .select { |i| i.type == :artifact }
                            .to_h { |i| [i.key, context.artifacts[i.key]] }

      # still set container-path env vars for scripts
      # node.inputs.select { |i| i.type == :artifact }.each do |input|
      #   env[input.key.upcase] = "/apricity/artifacts/#{input.key}"
      # end
      Console.debug(self, "run_node:starting", job_name: node.job_name, inputs: node.inputs, outputs: node.outputs)
      # node.outputs.each do |output|
      #   env[output.key.upcase] = "/apricity/artifacts/#{output.key}" if output.type == :artifact
      # end
      node.inputs.each do |input|
        case input.type
        # Commenting out for now...
        when :artifact
          # env[input.key.upcase] = "/apricity/artifacts/#{input.key}"
          # skip?
        when :value
          env[input.key.upcase] = context.value(input.key)
        else
          raise "Unknown input type #{input.type} for input #{input.key}"
        end
      end
      # node_events = run_node(node, env:)
      events.push(*run_node(node, env:, artifact_inputs:))
      node.outputs.each do |output|
        case output.type
        when :value
          context.values[output.key] = extract_value(events, output.key)
        when :artifact
          context.artifacts[output.key] = extract_value(events, output.key)
        else
          raise "Unknown output type #{output.type} for output #{output.key}"
        end
      end

      # Record node status (simple rule for now)
      status = events.any? { |e| e.status == "failure" } ? :failure : :success
      status = :skipped if events.empty?
      context.nodes[node.id] = status

      events
    end

    private

    def run(nodes, context: ExecutionContext.empty)
      events = []
      Console.debug(self, "run_pipeline:start", pipeline_name:, total_nodes: nodes.size)

      nodes.each do |node|
        node_events = run_node!(node, context:)
        events.push(*node_events)
        # raise "Pipeline failed at job #{node.job_name}" if node_events.any? { |e| e.status == "failure" }
      end

      Console.debug(self, "run_pipeline:complete", pipeline_name:, total_events: events.size)
      events
    end

    def extract_value(node, key)
      # key will be in one of the events' outputs
      node.each do |event|
        return event.outputs[key] if event.outputs.key?(key)
      end

      nil
    end

    def verify_conditions(node, context)
      if node.conditions.any? && !node.conditions.all? { |cond| Conditions.evaluate(cond, context) }
        Console.info(self, "run_pipeline:node_skipped", node_id: node.id, job_name: node.job_name,
                                                        action_name: node.action_name)
        context.nodes[node.id] = :skipped
        return false
      end

      true
    end

    def run_node(node, env: {}, artifact_inputs: {})
      events = []
      Console.debug(self, "run_node:steps_start", pipeline_name:, node_id: node.id, job_name: node.job_name,
                                                  action_name: node.action_name)
      node.steps.each do |step|
        events.concat(run_step(node, step, env:, artifact_inputs:))
      end
      events
    end

    def run_step(node, step, env: {}, artifact_inputs: {})
      Console.debug(self, "run_step:start", pipeline_name:, node_id: node.id, job_name: node.job_name,
                                            action_name: node.action_name, step_name: step.name)
      events = []
      events.push(*StepExecutor.new(step:, node:, env:, artifact_inputs:).perform)
      Console.debug(self, "run_step:complete", pipeline_name:, node_id: node.id, job_name: node.job_name,
                                               action_name: node.action_name, step_name: step.name)
      events
    end
  end
end
