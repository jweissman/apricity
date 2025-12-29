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
require_relative "apricity/pipeline/graph"
require_relative "apricity/pipeline/reducer"
require_relative "apricity/conditions"
require_relative "apricity/output_sink"
require_relative "apricity/plugins/plugin_registry"
require_relative "apricity/plugins/plugin_definition"
require_relative "apricity/job_execution"
require_relative "apricity/pipeline/runner"

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

  # Start/finish timestamps structure
  Timestamps = Data.define(:started_at, :finished_at)

  # rubocop:disable Metrics/ModuleLength
  module Run
    NodeState = Data.define(:id, :name, :status, :phase, :started_at, :finished_at, :step_states) do
      def self.for(node, status:, phase:, timestamps:, step_states:) = new(
        id: node.id, name: node.job_name,
        status:, phase:,
        started_at: timestamps.started_at,
        finished_at: timestamps.finished_at,
        step_states:
      )

      def duration_seconds = (finished_at - started_at).round(2)
    end

    StepState = Data.define(:name, :job, :status, :started_at, :finished_at) do
      def duration_seconds = started_at ? ((finished_at || Time.now) - started_at).round(2) : nil
    end

    State = Data.define(:pipeline, :nodes) do
      def self.empty(pipeline)
        states = {}
        nodes = Pipeline::Reducer.lower(pipeline)
        nodes.each do |node|
          states[node.id] = empty_node_state_for(node)
        end

        new(pipeline:, nodes: states)
      end

      def self.empty_node_state_for(node)
        NodeState.for(
          node,
          status: :pending,
          phase: :pending,
          timestamps: Timestamps[started_at: nil, finished_at: nil],
          step_states: []
        )
      end

      def reduce(event)
        new_states = nodes.dup
        handle_event(event, new_states)
        self.class.new(pipeline:, nodes: new_states)
      end

      def handle_event(event, node_states)
        case event.type
        when :job_started then job_started(event, node_states)
        when :job_skipped then job_skipped(event, node_states)
        when :job_finished then job_finished(event, node_states)
        when :step_started then step_started(event, node_states)
        when :step_finished then step_finished(event, node_states)
        end
      end

      def job_started(event, node_states)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: nil,
          phase: :running,
          timestamps: Timestamps[
            started_at: event.started_at,
            finished_at: nil
          ],
          step_states: initial_step_states(event.node)
        )
      end

      def job_skipped(event, node_states)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: :skipped,
          phase: :skipped,
          timestamps: Timestamps[
            started_at: event.skipped_at,
            finished_at: event.skipped_at
          ],
          step_states: []
        )
      end

      def job_finished(event, node_states)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: event.status,
          phase: :completed,
          timestamps: Timestamps[
            started_at: node_states[event.node.id]&.started_at,
            finished_at: event.finished_at
          ],
          step_states: node_states[event.node.id]&.step_states || []
        )
      end

      def step_started(event, node_states)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: node_state.status, phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: start_step_state(node_states[event.node.id]&.step_states, event)
        )
      end

      def step_finished(event, node_states)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: node_state.status, phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: update_step_states(node_states[event.node.id]&.step_states, event)
        )
      end

      def timestamps_for(node_state)
        Timestamps[
          started_at: node_state.started_at,
          finished_at: node_state.finished_at
        ]
      end

      def initial_step_states(node)
        node.steps.map do |step|
          StepState[
            name: step.name, job: node.job_name, status: :pending,
            started_at: nil, finished_at: nil
          ]
        end
      end

      def start_step_state(step_states, event)
        step_states.map do |step_state|
          next step_state unless step_state.job == event.node.job_name && step_state.name == event.step.name

          StepState[
            name: step_state.name,
            job: step_state.job,
            status: :running,
            started_at: event.started_at,
            finished_at: nil
          ]
        end
      end

      def update_step_states(step_states, event)
        step_states.map do |step_state|
          update_matching_step_state(step_state, event)
        end
      end

      def update_matching_step_state(step_state, event)
        return step_state unless step_state.job == event.node.job_name && step_state.name == event.step.name

        StepState[
          name: step_state.name,
          job: step_state.job,
          status: event.status,
          started_at: step_state.started_at,
          finished_at: event.finished_at
        ]
      end
    end

    Result = Data.define(:run, :started_at, :finished_at, :step_states, :final_run_state) do
      def duration_seconds = (finished_at - started_at).round(2)
      def failed_nodes = final_run_state.nodes.values.select { it.status == :failure }
      def retryable? = failed_nodes.any?
      def passed? = failed_nodes.empty?
    end

    Instance = Data.define(:id, :pipeline, :git_sha) do
      def self.create(pipeline, git_sha: nil) = new(id: SecureRandom.uuid, pipeline:, git_sha:)

      def perform(&)
        t0 = Time.now
        events = []
        step_states = runner.run do |event|
          events << event
          yield(event) if block_given?
        end
        final_run_state = events.reduce(State.empty(pipeline)) { |state, event| state.reduce(event) }
        t1 = Time.now
        Result[run: self, step_states:, final_run_state:, started_at: t0, finished_at: t1]
      end

      private

      def runner = Apricity::Pipeline::Runner.new(pipeline:)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
