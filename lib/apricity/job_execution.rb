# frozen_string_literal: true

module Apricity
  module JobExecution
    WORKING_DIR = "/work"

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

    # Events emitted during job execution
    module Events
      def self.prefix(event)
        "#{event.node.action_name}##{event.node.job_name}"
      end

      JobStarted = Data.define(:node) do
        def type = :job_started
        def pretty = "started job #{node.job_name}"
      end
      JobSkipped = Data.define(:node, :reason) do
        def type = :job_skipped
        def pretty = "skipped #{node.job_name} due to #{reason}"
      end
      JobFinished = Data.define(:node, :status) do
        def type = :job_finished
        def pretty = "finish job with status #{status}"
      end

      StepStarted = Data.define(:node, :step) do
        def type = :step_started
        def pretty = "started step #{step.name}"
      end
      StepFinished = Data.define(:node, :step, :status) do
        def type = :step_finished
        def pretty = "finished step #{step.name}"
      end

      StdoutChunk = Data.define(:node, :step, :chunk) do
        def type = :stdout_chunk
        def pretty = "(stdout chunk from step #{step.name})"
      end
      StderrChunk = Data.define(:node, :step, :chunk) do
        def type = :stderr_chunk
        def pretty = "(stderr chunk from step #{step.name})"
      end
    end

    # Internal class for planning job execution
    class Planner
      attr_reader :binds, :artifact_outputs, :working_dir, :prelude, :effective_working_dir

      def initialize(node:, env:, artifact_inputs:, config: Apricity::Configuration.instance)
        @node = node
        @env = env
        @artifact_inputs = artifact_inputs
        @working_dir = @effective_working_dir = WORKING_DIR
        @prelude = <<~SH
          set -euo pipefail
        SH
        @binds = []
        @artifact_outputs = {}
        @config = config
      end

      def call
        artifact_binds = setup_artifacts
        compute_bind_mounts(artifact_binds:)
        configure_env
        self
      end

      private

      attr_reader :node, :config, :artifact_inputs

      def configure_env
        @env["APRICITY_OUTPUT"] = "/tmp/apricity-values"
        @env["APRICITY_ARTIFACTS"] = "#{WORKING_DIR}/artifacts"
      end

      def input_artifacts = node.inputs.select { |i| i.type == :artifact }
      def output_artifacts = node.outputs.select { |o| o.type == :artifact }

      def setup_artifacts
        [
          *input_artifacts.map { |input| setup_input_artifact(input) },
          *output_artifacts.map { |output| setup_output_artifact(output) }
        ]
      end

      def setup_input_artifact(input)
        host_dir = artifact_inputs[input.key]
        raise "Missing artifact #{input.key}" unless host_dir

        "#{host_dir}:#{WORKING_DIR}/artifacts/#{input.key}:ro"
      end

      def setup_output_artifact(output)
        host_dir = Dir.mktmpdir("artifact-#{output.key}-")
        host_dir = File.realpath(host_dir)
        @artifact_outputs[output.key] = host_dir

        @prelude += "\nmkdir -p #{WORKING_DIR}/artifacts/#{output.key}"

        "#{host_dir}:#{WORKING_DIR}/artifacts/#{output.key}"
      end

      def compute_bind_mount(mount)
        case mount.type
        when :bind
          host_path = File.expand_path(mount.source)
          raise "Mount source does not exist: #{host_path}" unless File.exist?(host_path)

          # maybe need to expose this?
          @effective_working_dir = mount.target if mount.source == "."
          "#{host_path}:#{mount.target}:rw"
        else
          raise "Unknown mount type #{mount.type} for mount #{mount.source} -> #{mount.target}"
        end
      end

      def compute_bind_mounts(artifact_binds:)
        bind_mounts = [
          *node.mounts,
          *config.bind_mounts
        ].map do |mount|
          compute_bind_mount(mount)
        end

        @binds = [
          *artifact_binds,
          *bind_mounts
        ]
      end
    end

    # Executes a single step inside a Docker container
    class StepExecutor
      attr_reader :step, :env, :sink, :node

      def initialize(node:, step:, env:, sink: NullOutputSink.new)
        @step = step
        @env  = env
        @sink = sink
        @node = node
      end

      def perform(prelude:, container:, emit:, container_options: {})
        script = [prelude, step.run.lines.join("\n")].join("\n")
        exec_cmd = ["/bin/bash", "-lc", script]
        stdout, stderr, exit_code = execute(
          command: exec_cmd,
          container:, emit:,
          container_options:
        )
        raise JobExecutionError, "Step #{step.name} failed with exit code #{exit_code}" unless exit_code.zero?

        [stdout, stderr]
      end

      private

      def execute(command:, container:, emit:, container_options:)
        stdout = +""
        stderr = +""
        result = container.exec(command, **container_options) do |stream, chunk|
          klass = stream == :stdout ? Events::StdoutChunk : Events::StderrChunk
          event = klass[node:, step:, chunk:]
          emit[event]
          stream == :stdout ? stdout << chunk : stderr << chunk
        end
        [stdout, stderr, result[2]]
      end
    end

    # Collect outputs after execution
    # - Values are read from a designated file inside the container
    # - Artifacts are container-local during execution and exported explicitly at collect time
    class Collector
      attr_reader :node, :container, :artifact_outputs

      def initialize(node:, container:, artifact_outputs:)
        @node = node
        @container = container
        @artifact_outputs = artifact_outputs
      end

      def collect
        values = read_values
        pull_artifacts
        validate!(values:)
        values.merge(@artifact_outputs)
      end

      def read_values
        values = {}
        values_contents, _err, code = exec_stdout(%(cat "$APRICITY_OUTPUT" 2>/dev/null || true))
        if code.zero? && !values_contents.empty?
          values_contents.each_line do |line|
            key, value = line.strip.split("=", 2)
            values[key] = value if key && value
          end
        end
        values
      end

      def pull_artifacts
        @artifact_outputs.each do |key, host_dir|
          container_dir = "#{JobExecution::WORKING_DIR}/artifacts/#{key}"
          pull_artifact_from_container(container_dir, host_dir)
        end
      end

      def missing_outputs(values:)
        node.outputs.reject do |output|
          valid_output?(output, values:)
        end
      end

      def validate!(values:)
        return if validate(values:)

        missing = missing_outputs(values:).map { "'#{it.key}'" }
        message = if missing.length == 1
                    "Declared output #{missing.join} was not produced"
                  else
                    "Declared outputs #{missing.join(", ")} were not produced"
                  end
        message += " for job :#{node.job_name} of action :#{node.action_name}"

        raise JobExecutionError, message
      end

      def validate(values:)
        node.outputs.all? do |output|
          valid_output?(output, values:)
        end
      end

      def valid_output?(output, values:)
        if output.type == :value
          values.key?(output.key)
        elsif output.type == :artifact
          Dir.exist?(@artifact_outputs[output.key]) &&
            !Dir.empty?(@artifact_outputs[output.key])
        else
          raise JobExecutionError, "Unknown output type #{output.type} for output #{output.key}"
        end
      end

      private

      def pull_artifact_from_container(container_dir, host_dir)
        FileUtils.mkdir_p(host_dir)

        tar_data, _err, code = exec_stdout(
          %(cd "#{container_dir}" 2>/dev/null && tar -cf - .)
        )

        return if code != 0 || tar_data.empty?

        read_archive(tar_data, host_dir)
      end

      def read_archive(tar_data, dest_dir)
        Gem::Package::TarReader.new(StringIO.new(tar_data)) do |tar|
          tar.each do |entry|
            handle_tar_entry(entry, dest_dir)
            # dest = File.join(dest_dir, entry.full_name)
            # if entry.directory?
            #   FileUtils.mkdir_p(dest)
            # else
            #   FileUtils.mkdir_p(File.dirname(dest))
            #   File.binwrite(dest, entry.read)
            # end
          end
        end
      end

      def handle_tar_entry(entry, dest_dir)
        dest = File.join(dest_dir, entry.full_name)
        if entry.directory?
          FileUtils.mkdir_p(dest)
        else
          FileUtils.mkdir_p(File.dirname(dest))
          File.binwrite(dest, entry.read)
        end
      end

      def exec_stdout(cmd)
        out = +""
        err = +""
        result = container.exec(["/bin/sh", "-lc", cmd]) do |stream, chunk|
          stream == :stdout ? out << chunk : err << chunk
        end
        [out, err, result[2]]
      end
    end
  end
end
