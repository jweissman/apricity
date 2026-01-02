# frozen_string_literal: true

require_relative "run/timestamps"
require_relative "run/node_state"
require_relative "run/step_state"
require_relative "run/state"

module Apricity
  module Run
    Result = Data.define(:run, :started_at, :finished_at, :step_states, :final_run_state) do
      def duration_seconds = (finished_at - started_at).round(2)
      def failed_nodes = final_run_state.nodes.values.select { it.status == :failure }
      def retryable? = failed_nodes.any?
      def passed? = failed_nodes.empty?
    end

    Subscriber = Data.define(:queue) do
      def push(event) = queue << event
    end

    # Manage subscribers for run events
    class Subscriptions
      @subscribers = Hash.new { |h, k| h[k] = [] }

      def self.add_subscriber(run_id, subscriber)
        @subscribers[run_id] << subscriber
      end

      def self.remove_subscriber(run_id, subscriber)
        @subscribers[run_id].delete(subscriber)
      end

      def self.dispatch(run_id, event)
        @subscribers[run_id].each do |subscriber|
          subscriber.push(event)
        end
      end
    end

    # Simple in-memory event store for runs
    class EventStore
      @events = Hash.new { |h, k| h[k] = [] }
      def self.get_events(run_id) = @events[run_id]

      def self.append_event(run_id, event)
        $stdout.puts "[EventStore#append] #{event.type}: #{event.pretty}"
        @events[run_id] << event
        Subscriptions.dispatch(run_id, event)
      end
    end

    Instance = Data.define(:id, :pipeline, :git_sha) do
      def self.create(pipeline, git_sha: nil) = new(id: SecureRandom.uuid, pipeline:, git_sha:)

      def started_at
        Apricity::Run::EventStore.get_events(id)
                                 .find { |e| e.type == :job_started }&.started_at
      end

      def state
        Apricity::Run::EventStore.get_events(id).reduce(
          State.empty(pipeline)
        ) { |state, event| state.reduce(event) }
      end

      def finished? = status != :running

      def status
        current = state
        if current.nodes.values.all? { |ns| ns.status == :skipped }
          :skipped
        elsif current.nodes.values.any? { |ns| ns.status == :failure }
          :failure
        elsif current.nodes.values.all? { |ns| ns.status == :success }
          :success
        else
          :running
        end
      end

      def perform(&)
        t0 = Time.now
        events = []
        step_states = runner.run do |event|
          events << event
          yield(event) if block_given?
          EventStore.append_event(id, event)
        end
        final_run_state = events.reduce(State.empty(pipeline)) { |state, event| state.reduce(event) }
        t1 = Time.now
        Result[run: self, step_states:, final_run_state:, started_at: t0, finished_at: t1]
      end

      private

      def runner = Apricity::Pipeline::Runner.new(pipeline:)
    end
  end
end
