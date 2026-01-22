# frozen_string_literal: true

require "time"
require_relative "worker"

module Apricity
  # Helper to introspect docker resources
  class DockerInspector
    def self.list_managed_containers
      Docker::Container.all(all: true, filters: { label: ["apricity.managed=true"] }.to_json)
    end

    def self.redis = @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

    def self.list_orphaned_containers
      list_managed_containers.select do |container|
        orphaned_container?(container)
      rescue StandardError => e
        warn "DockerInspector: Error inspecting container #{container.id}: #{e.class}: #{e.message}"
        false
      end
    end

    def self.orphaned_ttl_seconds = ENV.fetch("APRICITY_ORPHANED_CONTAINER_TTL_SECONDS", 300).to_i

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    def self.orphaned_container?(container)
      info = container.json
      labels = info["Config"]["Labels"] || {}
      run_id = labels["apricity.run_id"]
      started_at = begin
        Time.parse(info["State"]["StartedAt"])
      rescue StandardError
        nil
      end

      puts "Considering container for run_id=#{run_id} for orphaned status"

      # consider orphaned if no lease and started more than 5 minutes ago
      return false unless started_at && (Time.now - started_at) > orphaned_ttl_seconds

      puts "Container started at #{started_at} (> #{orphaned_ttl_seconds}), checking lease status..."

      orphaned = redis.get("apricity:lease:#{run_id}").nil?
      if orphaned
        puts "orphaned container detected: #{container.id} (run_id=#{run_id}) kind=#{labels["apricity.kind"]}"
      else
        puts "run lease found for run_id=#{run_id}, not orphaned"

      end
      orphaned
    rescue StandardError => e
      warn "DockerInspector: Error inspecting container #{container.id}: #{e.class}: #{e.message}"
      false
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/AbcSize

    def self.list_managed_networks
      Docker::Network.all(filters: { label: ["apricity.managed=true"] }.to_json)
    end
  end

  # Helper to finalize jobs
  class JobFinalizer
    def initialize(halted_job)
      @halted_job = halted_job
    end

    def finalize_run_state
      run_store = Apricity::RunStore.instance
      run_id = halted_job.run_id
      run = run_store.get_run(run_id)
      return unless run && run.status == "running"

      puts "Reaper: Finalizing run #{run_id} as 'failed' due to orphaned container cleanup"
      run_store.set_run_status(run_id, "failed")
      # puts "Reaper: Appending JobFinished event for run #{run_id}"
      append_events(halted_job)
    rescue StandardError => e
      warn "Reaper: Error finalizing run #{run_id}: #{e.class}: #{e.message}"
      warn e.backtrace.join("\n")
    end

    private

    attr_reader :halted_job

    # append a synthetic event to the run's event log
    def append_events
      puts "!!! Reaper: Appending synthetic events for halted job run #{halted_job.run_id}"
      event_store = Apricity::Run::EventStore.instance
      # event_store.append_event(halted_job.run_id, step_finished_event(halted_job))
      event_store.append_event(halted_job.run_id, job_finished_event(halted_job))
      event_store.append_event(halted_job.run_id, pipeline_finished_event(halted_job))
    end

    # will need some way to track current step in redis for this!
    # def step_finished_event
    #   # puts " * Reaper: Creating StepFinished event for halted job run #{halted_job.run_id}"
    #   Apricity::JobExecution::Events::StepFinished.new(
    #     node: Apricity::JobExecution::Node.minimal(
    #       halted_job.node_id, job_name: "unknown", action_name: "unknown"
    #     ),
    #     step: Apricity::Model::Step.new(name: halted_job.step_name),
    #     status: "failure",
    #     started_at: Time.now,
    #     finished_at: Time.now
    #     # duration_seconds: 0.0
    #   )
    #   # puts " * Reaper: StepFinished event created: #{evt.pretty}"
    # end

    def job_finished_event
      puts " * Reaper: Creating JobFinished event for halted job run #{halted_job.run_id}"
      Apricity::JobExecution::Events::JobFinished.new(
        node: Apricity::JobExecution::Node.minimal(halted_job.node_id, job_name: "unknown", action_name: "unknown"),
        status: "failure",
        finished_at: Time.now,
        exception: StandardError.new("Job run finalized as 'failed' by Reaper due to orphaned container cleanup"),
        outputs: {}
      )
    end

    def pipeline_finished_event
      puts " * Reaper: Creating PipelineFinished event for halted job run #{halted_job.run_id}"
      Apricity::JobExecution::Events::PipelineFinished.new(
        pipeline_name: halted_job.pipeline_name,
        status: "failure",
        finished_at: Time.now,
        outputs_by_node: {}
      )
    end
  end

  # Background reaper to clean up stale docker resources
  class Reaper
    HaltedJob = Data.define(:pipeline_name, :run_id, :node_id, :step_name, :reason) do
      def self.from_orphaned_container(container)
        labels = container.info["Labels"] || {}
        new(
          pipeline_name: labels["apricity.pipeline_name"] || "unknown",
          run_id: labels["apricity.run_id"],
          node_id: labels["apricity.node_id"],
          step_name: labels["apricity.step_name"] || "unknown",
          reason: "orphaned container"
        )
      end

      def hash = run_id.hash
      def eql?(other) = other.is_a?(HaltedJob) && run_id == other.run_id
    end

    def initialize(interval_seconds: ENV.fetch("APRICITY_REAPER_INTERVAL_SECONDS", 600).to_i)
      @interval_seconds = interval_seconds
      @stop_requested = false
    end

    def start = Thread.new { reaping }
    def stop = @stop_requested = true

    private

    def reaping
      puts "Reaper started, running every #{@interval_seconds} seconds"
      until @stop_requested
        begin
          puts "Reaper: Starting reaping cycle..."
          reaping_cycle
          puts "Reaper: Reaping cycle complete."
        rescue StandardError => e
          warn "Reaper: Error during reaping cycle: #{e.class}: #{e.message}"
          warn e.backtrace.join("\n")
        end
        sleep @interval_seconds
      end
      puts "Reaper stopped"
    end

    def reaping_cycle
      teardown_stale_docker_containers
      teardown_orphaned_docker_containers
      teardown_stale_docker_networks
      # could clear inactive workers here too?
      cleanup_expired_run_leases
      cleanup_dead_workers
    end

    def teardown_stale_docker_containers
      DockerInspector.list_managed_containers.each do |container|
        info = container.json
        state = info["State"] || {}
        status = state["Status"]
        destroy_container(container) if %w[exited dead created paused].include?(status)
      rescue StandardError => e
        warn "Reaper: Error inspecting/removing container #{container.id}: #{e.class}: #{e.message}"
      end
    end

    def teardown_orphaned_docker_containers
      puts "Reaper: Checking for orphaned containers..."

      halted_jobs.compact.uniq.each do |halted|
        # finalize_run_state(halted)
        JobFinalizer.new(halted).finalize_run_state
      end

      DockerInspector.list_orphaned_containers.map do |container|
        destroy_container(container)
      end
    rescue StandardError => e
      warn "Reaper: Error finalizing orphaned runs: #{e.class}: #{e.message}"
      warn e.backtrace.join("\n")
    end

    def halted_jobs
      DockerInspector.list_orphaned_containers.map do |container|
        container_kind = container.info["Labels"]["apricity.kind"]
        halted_job = HaltedJob.from_orphaned_container(container) if container_kind == "job"
        # destroy_container(container)
        # puts "Reaper: Cleaned orphaned container #{container.id} for run #{halted_job&.run_id}"
        halted_job
      rescue StandardError => e
        warn "Reaper: Error inspecting/removing orphaned container #{container.id}: #{e.class}: #{e.message}"
      end
    end

    def teardown_stale_docker_networks
      DockerInspector.list_managed_networks.each do |network|
        info = network.json
        containers = info["Containers"] || {}
        if containers.empty?
          puts "Reaper: Removing stale network #{network.id} (no connected containers)"
          network.delete(force: true)
        end
      rescue StandardError => e
        warn "Reaper: Error inspecting/removing network #{network.id}: #{e.class}: #{e.message}"
      end
    end

    def destroy_container(container)
      puts "Reaper: Destroying container #{container.id}"
      container.delete(force: true)
    rescue StandardError => e
      warn "Reaper: Error removing container #{container.id}: #{e.class}: #{e.message}"
    end

    def cleanup_expired_run_leases
      Apricity::Worker::Registry.instance.list_leases.each do |lease|
        run_id = lease[:run_id]
        # _worker_id = lease[:worker_id]
        # _pipeline_slug = lease[:pipeline_slug]
        ttl = DockerInspector.redis.ttl("apricity:lease:#{run_id}")
        if ttl.negative?
          # puts "Reaper: Cleaning up expired lease for run #{run_id} (worker: #{worker_id}, pipeline: #{pipeline_slug})"
          Apricity::Worker::Registry.instance.release_run_lease(run_id)
        end
      end
    rescue StandardError => e
      warn "Reaper: Error cleaning up expired run leases: #{e.class}: #{e.message}"
      warn e.backtrace.join("\n")
    end

    def cleanup_dead_workers
      Apricity::Worker::Registry.list_workers.each do |worker|
        # puts worker.inspect
        worker_id = worker["worker_id"]
        last_seen_at = worker["last_seen_at"].to_i
        current_run_id = worker["current_run_id"]
        next unless (now - last_seen_at) > Apricity::Worker.worker_timeout_seconds

        # puts "Reaper: Cleaning up dead worker #{worker_id} (last seen at #{Time.at(last_seen_at)})"
        Apricity::Worker::Registry.instance.unregister_worker(worker_id)
        if current_run_id
          # puts "Reaper: Releasing run lease for run #{current_run_id} held by dead worker #{worker_id}"
          Apricity::Worker::Registry.instance.release_run_lease(current_run_id)
        end
      end
    end

    def now = Time.now.to_i
  end
end
