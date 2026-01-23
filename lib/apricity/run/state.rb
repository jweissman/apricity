# frozen_string_literal: true

module Apricity
  module Run
    # Helper to build NodeState instances
    module NodeStateBuilder
      def node_state_for(event, **opts)
        NodeState.for(event.node,
                      status: opts.fetch(:status, nil),
                      phase: opts.fetch(:phase, nil),
                      timestamps: opts.fetch(:timestamps,
                                             Timestamps[started_at: nil,
                                                        finished_at: nil]),
                      step_states: opts.fetch(:step_states, []),
                      annotations: opts.fetch(:annotations, {}))
      end

      def timestamps_for(node_state)
        Timestamps[
          started_at: node_state.started_at,
          finished_at: node_state.finished_at
        ]
      end

      def initial_step_states(node)
        node.steps.map do |step|
          StepState[name: step.name, job: node.job_name, status: :pending, started_at: nil, finished_at: nil]
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

    # State reducer to process events and update run state
    class StateReducer
      include NodeStateBuilder

      def handle_event(event, node_states, run_annotations, metadata)
        send(event.type, event, node_states, run_annotations, metadata) if respond_to?(event.type, true)
      end

      private

      def job_started(event, node_states, _run_annotations, _metadata)
        node_states[event.node.id] = node_state_for(
          event,
          phase: :running,
          timestamps: Timestamps[started_at: event.started_at,
                                 finished_at: nil],
          step_states: initial_step_states(event.node)
        )
      end

      def job_meta_updated(event, _node_states, _run_annotations, metadata)
        $stdout.puts "Updating metadata: #{event.key} = #{event.value}"
        metadata.merge!({ event.key => event.value })
      end

      def job_skipped(event, node_states, _run_annotations, _metadata)
        node_states[event.node.id] = node_state_for(
          event,
          status: :skipped,
          phase: :skipped,
          timestamps: Timestamps[started_at: event.skipped_at,
                                 finished_at: event.skipped_at]
        )
      end

      def job_finished(event, node_states, _run_annotations, _metadata)
        node_states[event.node.id] = node_state_for(
          event,
          status: event.status,
          phase: :completed,
          timestamps: Timestamps[started_at: node_states[event.node.id]&.started_at,
                                 finished_at: event.finished_at],
          step_states: node_states[event.node.id]&.step_states || []
        )
      end

      def job_annotated(event, node_states, _run_annotations, _metadata)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = node_state_for(
          event,
          status: node_state.status,
          phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: node_state.step_states,
          annotations: node_state.annotations.merge(event.annotations)
        )
      end

      def step_started(event, node_states, _run_annotations, _metadata)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = node_state_for(
          event,
          status: node_state.status,
          phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: start_step_state(node_states[event.node.id]&.step_states, event)
        )
      end

      def step_finished(event, node_states, _run_annotations, _metadata)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = node_state_for(
          event,
          status: node_state.status,
          phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: update_step_states(node_states[event.node.id]&.step_states, event)
        )
      end

      def pipeline_annotated(event, _node_states, run_annotations, _metadata)
        run_annotations.merge!(event.annotations)
      end
    end

    State = Data.define(:pipeline, :nodes, :annotations, :metadata) do
      def self.empty(pipeline)
        states = {}
        nodes = Pipeline::Lowerer.lower(pipeline)
        nodes.each do |node|
          states[node.id] = empty_node_state_for(node)
        end

        new(pipeline:, nodes: states, annotations: {}, metadata: {})
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
        updated_annotations = annotations.dup
        new_metadata = metadata.dup
        reducer = StateReducer.new
        reducer.handle_event(event, new_states, updated_annotations, new_metadata)
        State[pipeline:, nodes: new_states, annotations: updated_annotations, metadata: new_metadata]
      end
    end
  end
end
