# frozen_string_literal: true

require_relative "job_execution/apricity_dir"
require_relative "job_execution/default_read_timeout"
require_relative "job_execution/docker_helpers"
require_relative "job_execution/events"
require_relative "job_execution/node"
require_relative "job_execution/path_resolver"
require_relative "job_execution/pipeline_state_context"
require_relative "job_execution/result"
require_relative "job_execution/working_dir"
require_relative "job_execution/workspace"
module Apricity
  module JobExecution
    # Internal class for managing artifact storage paths
    class ArtifactStore
      DEFAULT_ROOT = File.join(Dir.pwd, ".apricity").freeze
      def initialize(run:, node:, host_visible_artifact_root: DEFAULT_ROOT)
        @run = run
        @node = node
        @host_visible_artifact_root = host_visible_artifact_root
      end

      def output_dir(artifact_key) = self.class.path_for(run:, node:, artifact_key:, host_visible_artifact_root:)

      # Given run_id, job_id, artifact_key return a host directory path guaranteed to exist and be docker-safe
      def self.path_for(run:, node:, artifact_key:, host_visible_artifact_root: DEFAULT_ROOT)
        run_id = run.id
        pipeline_name = run.pipeline&.name&.gsub(/[^a-zA-Z0-9_-]/, "_") || "unknown-pipeline"
        job_id = node.id.gsub(/[^a-zA-Z0-9_-]/, "_")
        base_dir = File.join(host_visible_artifact_root,
                             "pipelines", pipeline_name, "runs", run_id, "artifacts", job_id)
        # warn "!!! Creating artifact directory #{base_dir.inspect} for artifact key #{artifact_key.inspect}"
        FileUtils.mkdir_p(base_dir)
        File.join(base_dir, artifact_key)
      end

      private

      attr_reader :run, :node, :host_visible_artifact_root
    end

    Plan = Data.define(:binds, :artifact_outputs, :working_dir, :env, :prelude)

    # Internal class for planning job execution
    class Planner
      attr_reader :binds, :artifact_outputs, :working_dir, :env

      def initialize(run:, node:, env:, artifact_inputs:, pipeline_root:)
        @run = run
        @node = node
        @env = env.merge(node.env || {})
        @artifact_inputs = artifact_inputs
        @working_dir = WORKING_DIR
        @host_workdir = nil
        @prelude = ""
        @binds = []
        @artifact_outputs = {}
        @pipeline_root = pipeline_root
      end

      def call
        artifact_binds = setup_artifacts
        compute_bind_mounts(artifact_binds:)
        configure_env
        Plan[binds:, artifact_outputs:, working_dir:, env:, prelude:]
      end

      def prelude = @prelude + "\nmkdir -p #{@working_dir}\ncd #{@working_dir}\n"

      private

      attr_reader :node, :artifact_inputs, :pipeline_root

      def artifact_store = @artifact_store ||= ArtifactStore.new(run: @run, node: @node)
      def config = Apricity::Configuration.instance
      def paths = @paths ||= PathResolver.new(root: pipeline_root)

      def configure_env
        @env["APRICITY_OUTPUT"] = "/tmp/apricity-values"
        @env["APRICITY_ARTIFACTS"] = File.join(APRICITY_DIR, "artifacts")
      end

      def artifact_root = paths.resolve(store.host_visible_artifact_root)
      def input_artifacts = node.inputs.select { |i| i.type == :artifact }
      def output_artifacts = node.outputs.select { |o| o.type == :artifact }

      def setup_artifacts
        @prelude += "\nmkdir -p #{APRICITY_DIR}/artifacts"
        [*input_artifacts.map { setup_input_artifact(it) }, *output_artifacts.map { setup_output_artifact(it) }]
      end

      def setup_input_artifact(input)
        key = input.key
        host_dir = artifact_inputs[key] || artifact_inputs[key.to_s]

        raise "Missing artifact #{key}" unless host_dir
        raise "Artifact input dir does not exist: #{host_dir}" unless Dir.exist?(host_dir)

        if DockerHelpers.dind?
          @prelude += "\nmkdir -p #{APRICITY_DIR}/artifacts"
          return nil
        end

        bind_source = paths.resolve(host_dir)
        "#{bind_source}:#{APRICITY_DIR}/artifacts/#{key}:ro"
      end

      def setup_output_artifact(output)
        key = output.key

        if DockerHelpers.dind?
          # Container-local artifacts; step owns the subdir
          @prelude += "\nmkdir -p #{APRICITY_DIR}/artifacts/#{key}"
          @artifact_outputs[key] = "#{APRICITY_DIR}/artifacts/#{key}"
          return nil
        end

        output_dir = artifact_store.output_dir(key)
        FileUtils.mkdir_p(output_dir)
        bind_source = @artifact_outputs[key] = output_dir
        "#{bind_source}:#{APRICITY_DIR}/artifacts/#{key}"
      end

      def compute_binding(mount, workspace)
        host_path =
          if workspace && mount.target == workspace.target
            workspace.host_path
          else
            mount.source
          end

        raise "Bind mount source does not exist: #{host_path.inspect}" unless File.exist?(host_path)

        "#{host_path}:#{mount.target}:rw"
      end

      def compute_bind_mounts(artifact_binds:)
        return @binds = artifact_binds.compact if DockerHelpers.dind?

        mounts = [*normalized_mounts, *config.bind_mounts].select { |m| m.type == :bind }

        workspace = Workspace.resolve(mounts, resolver: paths)
        apply_workspace(workspace) if workspace

        bind_mounts = mounts.map { |m| compute_binding(m, workspace) }

        @binds = [*artifact_binds, *bind_mounts]
      end

      def normalized_mounts
        node.mounts.map do |mount|
          next mount unless mount.type == :bind && !mount.source.start_with?("/")

          Model::Mount[source: File.expand_path(mount.source), target: mount.target, type: mount.type]
        end
      end

      def apply_workspace(workspace)
        @env["APRICITY_HOST_WORKDIR"] = workspace.host_path
        # @env["APRICITY_HOST_ARTIFACT_ROOT"] = File.join(workspace.host_path, ".apricity")
      end

      def host_path_for(path)
        return path unless @host_workdir

        # If a path is inside WORKING_DIR (/work), map it into the host workdir
        wd = WORKING_DIR # "/work"
        if path == wd
          @host_workdir
        elsif path.start_with?("#{wd}/")
          File.join(@host_workdir, path.delete_prefix("#{wd}/"))
        else
          path
        end
      end
    end

    StepMetadata = Data.define(:working_dir, :binds)
    # Executes a single step inside a Docker container
    class StepExecutor
      attr_reader :step, :env, :sink, :node

      def initialize(node:, step:, env:, meta:, sink: NullOutputSink.new)
        @step = step
        @env  = env
        @sink = sink
        @node = node
        @meta = meta
      end

      def perform(prelude:, container:, emit:)
        script = script_for_step(prelude:, step:)
        command = ["/bin/bash", "-lc", script]
        stdout, stderr, exit_code = execute(command:, container:, emit:) # , container_options:)
        raise JobExecutionError, "Step #{step.name} failed with exit code #{exit_code}" unless exit_code.zero?

        [stdout, stderr]
      end

      private

      # def execute(command:, container:, emit:)
      #   execute!(command:, container:, emit:)
      # rescue Docker::Error::DockerError => e
      #   raise <<~MSG
      #     Docker error during execution of step #{step.name}: #{e.class}: #{e.message}
      #     Working directory: #{@meta.working_dir.inspect}
      #     Binds: #{@meta.binds.inspect}
      #   MSG
      # end

      def execute(command:, container:, emit:)
        stdout = +""
        stderr = +""

        result = container.exec(command) do |stream, chunk|
          klass = stream == :stdout ? Events::StdoutChunk : Events::StderrChunk
          event = klass[node:, step:, chunk:]
          emit[event]
          stream == :stdout ? stdout << chunk : stderr << chunk
        end
        [stdout, stderr, result[2]]
      end

      def script_for_step(prelude:, step:)
        if step.uses?
          action = Apricity::Actions::ActionRegistry.instance.resolve(step.uses)

          shell_cmd = action.new(job_id: node.id, step_id: step.name,
                                 options: step.with || {}).to_shell
          [prelude, shell_cmd, "sync"].join("\n")
        else
          [prelude, step.run.source, "sync"].join("\n")
        end
      end
    end

    # Collect outputs after execution
    # - Values are read from a designated file inside the container
    # - Artifacts are container-local during execution and exported explicitly at collect time
    class Collector
      attr_reader :node, :container, :artifact_outputs

      def initialize(run:, node:, container:, artifact_outputs:)
        @run = run
        @node = node
        @container = container
        @artifact_outputs = artifact_outputs
      end

      def collect
        values = read_values
        pull_artifacts if DockerHelpers.dind?
        merged = values.merge(@artifact_outputs)
        validate!(values: merged)
        merged
      end

      private

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
        @artifact_outputs.each do |key, _container_dir|
          container_dir = "#{APRICITY_DIR}/artifacts/#{key}"
          host_dir = ArtifactStore.path_for(run: @run, node:, artifact_key: key)
          pull_artifact_from_container(container_dir, host_dir)
          @artifact_outputs[key] = host_dir
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
          values.key?(output.key) && values[output.key.to_s]
        elsif output.type == :artifact
          dir = values[output.key]
          dir && Dir.exist?(dir) && !Dir.empty?(dir)
        end
      end

      def pull_artifact_from_container(container_dir, host_dir)
        FileUtils.mkdir_p(host_dir)

        # Guard: if the dir doesn't exist in the container, don't try to tar it.
        _out, _err, code = exec_stdout(%(test -d "#{container_dir}"))
        return unless code.zero?

        tar_data, _err, code = exec_stdout(%(cd "#{container_dir}" 2>/dev/null && tar -cf - .))
        return unless code.zero?
        return if (tar_data || []).empty?

        read_archive(tar_data, host_dir)
      end

      def exec_stdout(cmd)
        out = +"".b
        err = +""
        result = container.exec(["/bin/sh", "-lc", cmd]) do |stream, chunk|
          if stream == :stdout
            out << chunk.b
          else
            err << chunk
          end
        end
        [out, err, result[2]]
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
          env["DATABASE_URL"] = assemble_estimated_postgres_url(service)
          env["POSTGRES_HOST"] = service.name
        else warn("No environment variable guesses for service image #{service.image}")
        end
      end

      def assemble_estimated_postgres_url(service)
        "postgres://#{service.env_vars["POSTGRES_USER"]}:" \
          "#{service.env_vars["POSTGRES_PASSWORD"]}@" \
          "#{service.name}:5432/#{service.env_vars["POSTGRES_DB"]}"
      end
    end

    # Dependencies for the orchestrator
    module OrchestrationDependencies
      def planner
        @planner ||= JobExecution::Planner.new(
          run: @run, node:, env:, artifact_inputs:, pipeline_root:
        )
      end

      def collector
        @collector ||= JobExecution::Collector.new(run: @run, node:, container:,
                                                   artifact_outputs: @artifact_outputs)
      end

      def default_sink = Apricity::Configuration.instance.output_sink || NullOutputSink.new
    end

    # Represents a Docker container session
    class ContainerSession
      def initialize(image:, binds:, env:, working_dir:, network:)
        @image = image
        @binds = binds
        @env = env
        @working_dir = working_dir
        @network = network
      end

      def start
        container.start
        container.refresh!
        raise "Container failed to start" unless running?

        # we could return container but better to encapsulate
        self
      end

      def exec(cmd, **options, &) = container.exec(cmd, **options.merge(container_options), &)
      def delete = container.delete(force: true)
      def archive_in(src_paths, dest_path) = container.archive_in(src_paths, dest_path)
      def running? = container.json.dig("State", "Running")

      private

      def container
        @container ||= Docker::Container.create(
          "Image" => @image,
          "AttachStdout" => true, "AttachStderr" => true,
          "Cmd" => ["/bin/sh", "-lc", "tail -f /dev/null"],
          "HostConfig" => { "Binds" => @binds }
            .merge(@network ? { "NetworkMode" => @network.id } : {}),
          **container_options
        )
      end

      def container_options
        { "Env" => @env.map { |k, v| "#{k}=#{v}" },
          "WorkingDir" => @working_dir,
          "Tty" => false }
      end
    end

    # Executes a single job inside a Docker container
    class Orchestrator
      include ServiceOrchestration
      include OrchestrationDependencies

      attr_reader :node, :env, :artifact_inputs, :sink

      def initialize(run:, node:, env: {}, artifact_inputs: {}, sink: default_sink)
        @run = run
        @node = node
        @env = env
        @artifact_inputs = artifact_inputs
        @working_dir = JobExecution::WORKING_DIR
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
        network&.delete(force: true)
      end

      protected

      def pipeline_root = @pipeline_root ||= File.dirname(File.expand_path(@run.pipeline.path || Dir.pwd))

      def run_job
        bootstrap && plan
        outcomes = execute
        outputs = collector.collect
        emit(JobExecution::Events::JobFinished[node:, status: :success, finished_at: Time.now, outputs:])
        JobExecution::Result[outcomes:, outputs:]
      ensure
        container&.delete
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
        the_plan = planner.call
        @binds = the_plan.binds.compact
        @artifact_outputs = the_plan.artifact_outputs
        @working_dir = the_plan.working_dir
        @prelude += the_plan.prelude
        @env = the_plan.env
      end

      # Execute the steps inside a Docker container
      def execute
        # start_container
        container.start
        copy_input_artifacts if DockerHelpers.dind?
        node.steps.map do |step|
          @last_step_executed = step
          step_outcome = execute_step(step)
          emit(JobExecution::Events::StepFinished[node:, step:, status: step_outcome.status, finished_at: Time.now])
          step_outcome
        end
      end

      def execute_step(step)
        emit(JobExecution::Events::StepStarted[node:, step:, started_at: Time.now])
        meta = StepMetadata[working_dir: @working_dir, binds: @binds]
        step_executor = JobExecution::StepExecutor.new(step:, env:, sink:, node:, meta:)
        stdout, stderr = step_executor.perform(prelude: @prelude, container:, emit: -> { emit it })
        success_outcome(stdout:, stderr:)
      end

      private

      def copy_input_artifacts = artifact_inputs.each { |key, host_dir| copy_input_artifact(key, host_dir) }

      def copy_input_artifact(key, host_dir)
        container_target_dir = "#{APRICITY_DIR}/artifacts/#{key}"

        container.exec(["/bin/sh", "-lc", "mkdir -p #{container_target_dir}"])

        dotfiles = [".", ".."]
        entries = Dir.glob(File.join(host_dir, "{*,.*}"), File::FNM_DOTMATCH)
                     .reject { |p| dotfiles.include?(File.basename(p)) }

        return if entries.empty?

        container.archive_in(entries, container_target_dir)
      end

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

      def merged_env = env.merge(service_environment_variables(node)).merge(service_raw_env_vars(node) || {})

      def container
        @container ||= ContainerSession.new(image:, binds: @binds, env: merged_env, working_dir: @working_dir, network:)
      end

      def failure_outcome(exception:) = Model::StepOutcome.failure(node, step, stdout: "", stderr: "", exception:)
      def success_outcome(stdout:, stderr:) = Model::StepOutcome.success(node, step, stdout:, stderr:)
      def image = "#{node.runs_on.name}:#{node.runs_on.version}"
    end
  end
end
