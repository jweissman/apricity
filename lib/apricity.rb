# frozen_string_literal: true

require "console"
require "securerandom"
require "base64"
require "docker-api"
require "rubygems/package"
require "stringio"

require_relative "apricity/version"
require_relative "apricity/model"
require_relative "apricity/pipeline_graph"

module Apricity
  class Error < StandardError; end
  class JobExecutionError < Error; end

  # class Configuration
  #   attr_accessor :bind_mounts

  #   def initialize
  #     @bind_mounts = []
  #   end
  # end

  # def self.configure
  #   @configuration ||= Configuration.new
  #   yield(@configuration) if block_given?
  #   @configuration
  # end

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

  JobExecutionResult = Data.define(:events, :outputs) do
    def passed? = events.all?(&:successful?)
    def failed? = events.any?(&:failed?)
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

  # Executes node steps inside a container
  class JobExecutor
    WORKING_DIR = "/work"
    DEFAULT_READ_TIMEOUT = 300 # seconds
    attr_reader :node, :env, :artifact_inputs

    def initialize(node:, env: {}, artifact_inputs: {})
      @node = node
      @env  = env
      @artifact_inputs = artifact_inputs
      @effective_working_dir = WORKING_DIR
      @last_step_executed = nil
      @prelude = <<~SH
        set -euo pipefail
        mkdir -p /apricity/outputs
      SH
    end

    def perform
      bootstrap
      plan
      events = execute
      outputs = collect
      JobExecutionResult[events:, outputs:]
    rescue JobExecutionError => e
      Console.error(self, "run_step:error", message: e.message, job_name: node.job_name, step_name: step&.name)
      JobExecutionResult[events: [failure_event(exception: e)], outputs: {}]
    ensure
      FileUtils.remove_entry(@output_dir) if @output_dir && File.exist?(@output_dir)

      container&.delete(force: true)
    end

    protected

    def bootstrap
      configure_docker
      construct_image
    end

    def plan
      bind_mounts = [
        *node.mounts
        # *Apricity.configure.bind_mounts
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

      host_workspace =
        if (mount = node.mounts.find { |m| m.source == "." })
          File.expand_path(mount.source)     # ← host project dir
        else
          Dir.mktmpdir("apricity-workspace") # fallback
        end
      @host_scratch_root = File.join(host_workspace, ".apricity")
      FileUtils.mkdir_p(@host_scratch_root)

      @output_dir = Dir.mktmpdir("apricity-outputs-", host_workspace) # , @host_scratch_root)
      @output_dir = File.realpath(@output_dir)
      File.chmod(0o777, @output_dir) # make sure container can write

      @container_workspace =
        if (mount = node.mounts.find { |m| m.source == "." })
          mount.target # e.g. /work/app
        else
          WORKING_DIR
        end

      @container_scratch_root = File.join(@container_workspace, ".apricity")
      @prelude += <<~SH
        mkdir -p #{@container_scratch_root}
        mkdir -p #{WORKING_DIR}/artifacts
      SH

      env["APRICITY_OUTPUT"] = "/apricity/outputs/values.txt"
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
        # host_dir = Dir.mktmpdir("apricity-artifact-#{output.key}") # but the job just produces to that dir name directly
        host_dir = Dir.mktmpdir("artifact-#{output.key}-", @host_scratch_root)
        host_dir = File.realpath(host_dir)
        @artifact_outputs[output.key] = host_dir
        artifact_binds << "#{host_dir}:#{WORKING_DIR}/artifacts/#{output.key}"

        @prelude << "\nmkdir -p #{WORKING_DIR}/artifacts/#{output.key}"
      end

      @binds = [
        "#{@output_dir}:/apricity/outputs",
        # "#{@host_scratch_root}:#{@container_scratch_root}",
        *artifact_binds,
        *bind_mounts
      ]
      @binds.each do |b|
        src = b.split(":", 2).first
        next if src.start_with?("/") && File.exist?(src) # rough check
      end

      Console.debug(self, "plan:container_config", binds: @binds, env:, image:, job_name: node.job_name)
    end

    # Execute the steps inside a Docker container
    def execute
      events = []
      container.start

      setup_script = <<~SH
        : > "$APRICITY_OUTPUT"
      SH
      container.exec(
        ["/bin/sh", "-c", setup_script],
        "Env" => env.map { |k, v| "#{k}=#{v}" },
        "WorkingDir" => @effective_working_dir,
        "Tty" => false
      ) do |stream, chunk|
        case stream
        when :stdout
          $stdout.print "[SETUP STDOUT] #{chunk}"
        when :stderr
          $stderr.print "[SETUP STDERR] #{chunk}"
        end
      end

      # run steps with docker exec
      node.steps.each do |step|
        @last_step_executed = step
        stdout = +""
        stderr = +""
        # cmd = step.run.lines.map(&:chomp)
        script = [@prelude, step.run.lines.join("\n"), "sync"].join("\n")
        exec_cmd = [
          "/bin/bash",
          "-lc",
          script
        ]
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
            $stdout.print chunk
            stdout << chunk
          when :stderr
            $stderr.print chunk
            stderr << chunk
          end
        end
        exit_code = exec_result[2]
        raise JobExecutionError, "Step #{step.name} failed with exit code #{exit_code}" unless exit_code.zero?

        event = success_event(stdout:, stderr:)
        # Console.info(event: event.inspect)
        Console.info("[#{event.status.upcase}] #{event.job} :: #{event.step}")
        events << event
        Console.debug(self, "execute:step_complete", container_id: container.id, job_name: node.job_name,
                                                     action_name: node.action_name, step_name: step.name,
                                                     stdout_size: stdout.size, stderr_size: stderr.size)
      end

      Console.debug(self, "execute:container_complete", container_id: container.id, job_name: node.job_name,
                                                        action_name: node.action_name)

      events
    end

    def collect
      output_elements = {}

      values_contents, _err, code = exec_stdout(%(cat "$APRICITY_OUTPUT" 2>/dev/null || true))
      if code.zero? && !values_contents.empty?
        values_contents.each_line do |line|
          key, value = line.strip.split("=", 2)
          output_elements[key] = value if key && value
        end
      end
      # values_file = File.join(@output_dir, "values.txt")
      # warn "DEBUG: host values file exists? #{File.exist?(values_file)}"
      # warn "DEBUG: host values contents:"
      # begin
      #   warn File.read(values_file)
      # rescue StandardError
      #   warn("unreadable")
      # end
      # if File.exist?(values_file)
      #   File.readlines(values_file).each do |line|
      #     key, value = line.strip.split("=", 2)
      #     output_elements[key] = value if key && value
      #   end
      # end

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
        # warn "DEBUG: values.txt contents:"
        # warn File.read(values_file) if File.exist?(values_file)

        warn "DEBUG: artifact dirs:"
        @artifact_outputs.each do |k, v|
          warn "#{k}: #{begin
            Dir.children(v).inspect
          rescue StandardError
            "missing"
          end}"
        end
        raise JobExecutionError, message
      end
      output_elements.merge(@artifact_outputs)
    end

    private

    require "rubygems/package"
    require "stringio"

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

    def failure_event(exception:) = Model::Event.failure(
      node, step, stdout: "", stderr: "", exception:
    )

    def success_event(stdout:, stderr:) = Model::Event.success(
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

    def run!
      nodes = PipelineReducer.lower(pipeline)
      graph = PipelineGraph.new(nodes)
      ordered_nodes = graph.topological_sort
      context = ExecutionContext[{}, {}, {}, graph.dependencies]
      run(ordered_nodes, context:)
    end

    def run_node!(node, context: ExecutionContext.empty)
      upstream = context.dependencies[node.id] || []
      if upstream.any? { |id| context.nodes[id] != :success }
        context.nodes[node.id] = :skipped
        events = [Model::Event.skipped(node, node.steps.first, reason: "Upstream job failure")]
        return JobExecutionResult[events:, outputs: {}]
      end

      unless verify_conditions(node, context)
        context.nodes[node.id] = :skipped
        events = [Model::Event.skipped(node, node.steps.first, reason: "Conditions not met")]
        return JobExecutionResult[events:, outputs: {}]
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
      result = run_node(node, env:, artifact_inputs:)
      if result.passed?
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

      # Record node status
      status = result.passed? ? :success : :failure
      status = :skipped if result.events.empty?
      context.nodes[node.id] = status

      result
    end

    private

    def run(nodes, context: ExecutionContext.empty) = nodes
      .flat_map { run_node!(it, context:).events }

    def extract_value(outputs, key) = (outputs[key] if outputs.key?(key))

    def verify_conditions(node, context)
      node.conditions.none? || node.conditions.all? { it.evaluate(context) }
    end

    def run_node(node, env: {}, artifact_inputs: {}) = JobExecutor.new(
      node:, env:, artifact_inputs:
    ).perform
  end
end
