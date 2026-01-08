# frozen_string_literal: true

require_relative "job_execution/working_dir"
require_relative "job_execution/default_read_timeout"
require_relative "job_execution/node"
require_relative "job_execution/pipeline_state_context"
require_relative "job_execution/result"
require_relative "job_execution/events"

module Apricity
  module JobExecution
    # Internal class for planning job execution
    class Planner
      attr_reader :binds, :artifact_outputs, :working_dir, :prelude, :effective_working_dir, :env

      def initialize(node:, env:, artifact_inputs:, config: Apricity::Configuration.instance)
        @node = node
        # $stdout.puts("Planning job execution for node #{node.id} with node envars #{node.env}")
        @env = env.merge(node.env || {})
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
        script = [prelude, step.run.source].join("\n")
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
          Console.info(self, "collect_artifact", artifact_key: key, container_dir:, host_dir:)
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

    JobContext = Data.define(:node, :env, :artifact_outputs)

    # Handles service orchestration for a job
    module ServiceOrchestration
      def start_services(network)
        return {} unless node.services && !node.services.empty?

        service_map = {}
        node.services.map { create_service(it, network, service_map) }
        service_map
      end

      def create_service(service, network, service_map)
        Docker::Image.create("fromImage" => service.image)

        service_map[service.image] = Docker::Container.create(
          "Image" => service.image, "Env" => service.env_vars.map { |k, v| "#{k}=#{v}" },
          "HostConfig" => { "NetworkMode" => network.id },
          "NetworkingConfig" => {
            "EndpointsConfig" => {
              network.id => { "Aliases" => [service.name] }
            }
          }
        ).tap(&:start)
      end

      def service_environment_variables(node)
        env = {}
        node.services.each do |service|
          guess_service_environment_variables(env, service)
        end
        env
      end

      def service_raw_env_vars(node)
        envars = node.services.flat_map(&:env_vars)
        envars.reduce(&:merge)
      end

      def guess_service_environment_variables(env, service)
        case service.image
        when /^redis/
          env["REDIS_URL"] = "redis://#{service.name}:6379"
        when /^postgres/
          env["DATABASE_URL"] =
            "postgres://#{service.env_vars["POSTGRES_USER"]}:" \
            "#{service.env_vars["POSTGRES_PASSWORD"]}@" \
            "#{service.name}:5432/#{service.env_vars["POSTGRES_DB"]}"
          env["POSTGRES_HOST"] = service.name
        else warn("No environment variable guesses for service image #{service.image}")
        end
      end
    end

    # Dependencies for the orchestrator
    module OrchestrationDependencies
      def planner = @planner ||= JobExecution::Planner.new(node:, env:, artifact_inputs:, config: Apricity::Configuration.instance)
      def collector = @collector ||= JobExecution::Collector.new(node:, container:, artifact_outputs: @artifact_outputs)
    end

    # Executes a single job inside a Docker container
    class Orchestrator
      include ServiceOrchestration
      include OrchestrationDependencies

      attr_reader :node, :env, :artifact_inputs, :sink

      def initialize(node:, env: {}, artifact_inputs: {},
                     sink: Apricity::Configuration.instance.output_sink || NullOutputSink.new)
        @node = node
        @env = env
        @artifact_inputs = artifact_inputs
        @effective_working_dir = JobExecution::WORKING_DIR
        @last_step_executed = nil
        @prelude = "set -euo pipefail\n"
        @sink = sink
      end

      def perform
        emit(JobExecution::Events::JobStarted[node:, started_at: Time.now])
        run_job
      rescue JobExecutionError => e
        handle_failure(e)
      ensure
        services&.each_value { |container| container.delete(force: true) }
        container&.delete(force: true)
        network&.delete(force: true)
      end

      protected

      def run_job
        bootstrap && plan
        outcomes = execute
        outputs = collector.collect
        emit(JobExecution::Events::JobFinished[node:, status: :success, finished_at: Time.now])
        JobExecution::Result[outcomes:, outputs:]
      end

      def handle_failure(exception)
        Console.error(self, "run_step:error", message: exception.message, job_name: node.job_name,
                                              step_name: step&.name)
        emit(JobExecution::Events::JobFinished[node:, status: :failure, finished_at: Time.now, exception:])
        JobExecution::Result[outcomes: [failure_outcome(exception:)], outputs: {}]
      end

      def bootstrap = configure_docker && construct_image && services

      def services
        return {} unless network

        @services ||= start_services(network)
      end

      def plan
        planner.call
        @binds                 = planner.binds
        @artifact_outputs      = planner.artifact_outputs
        @effective_working_dir = planner.effective_working_dir
        @prelude += planner.prelude
        @env = planner.env
      end

      # Execute the steps inside a Docker container
      def execute
        container.start
        node.steps.map do |step|
          emit(JobExecution::Events::StepStarted[node:, step:, started_at: Time.now])
          @last_step_executed = step
          step_outcome = execute_step(step)
          emit(JobExecution::Events::StepFinished[node:, step:, status: step_outcome.status, finished_at: Time.now])
          step_outcome
        end
      end

      def execute_step(step)
        stdout, stderr = JobExecution::StepExecutor.new(step:, env:, sink:, node:).perform(
          prelude: @prelude, container:,
          emit: ->(event) { emit(event) },
          container_options: common_container_options
        )
        success_outcome(stdout:, stderr:)
      end

      private

      def emit(event)
        @sink&.call(event)
        node.plugins&.each { |plugin| plugin.handle(event, context: context_for(node), emitter: -> { emit it }) }
      end

      def context_for(node) = JobContext[node:, env:, artifact_outputs: @artifact_outputs]
      def step = @last_step_executed
      def configure_docker = Docker.options[:read_timeout] = DEFAULT_READ_TIMEOUT

      def network
        return nil if node.services.to_a.empty?

        @network ||= Docker::Network.create("apricity-#{node.id}")
      end

      def construct_image = Docker::Image.create("fromImage" => image)

      def common_container_options
        merged_env = env.merge(service_environment_variables(node))
                        .merge(service_raw_env_vars(node))
        { "Env" => merged_env.map { |k, v| "#{k}=#{v}" },
          "WorkingDir" => @effective_working_dir,
          "Tty" => false }
      end

      def container
        @container ||= Docker::Container.create(
          "Image" => image,
          "AttachStdout" => true, "AttachStderr" => true,
          "HostConfig" => { "Binds" => @binds }.merge(network ? { "NetworkMode" => network.id } : {}),
          "Cmd" => ["/bin/sh", "-lc", "while true; do sleep 3600; done"],
          **common_container_options
        )
      end

      def failure_outcome(exception:) = Model::StepOutcome.failure(node, step, stdout: "", stderr: "", exception:)
      def success_outcome(stdout:, stderr:) = Model::StepOutcome.success(node, step, stdout:, stderr:)
      def image = "#{node.runs_on.name}:#{node.runs_on.version}"
    end
  end
end
