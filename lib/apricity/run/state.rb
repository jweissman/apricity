# frozen_string_literal: true

module Apricity
  module Run
    # State reducer to process events and update run state
    class StateReducer
      def handle_event(event, node_states, run_annotations)
        send(event.type, event, node_states, run_annotations) if respond_to?(event.type, true)
      end

      def job_started(event, node_states, _run_annotations)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: nil,
          phase: :running,
          timestamps: Timestamps[started_at: event.started_at, finished_at: nil],
          step_states: initial_step_states(event.node)
        )
      end

      def job_skipped(event, node_states, _run_annotations)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: :skipped,
          phase: :skipped,
          timestamps: Timestamps[started_at: event.skipped_at, finished_at: event.skipped_at],
          step_states: []
        )
      end

      def job_finished(event, node_states, _run_annotations)
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: event.status,
          phase: :completed,
          timestamps: Timestamps[started_at: node_states[event.node.id]&.started_at, finished_at: event.finished_at],
          step_states: node_states[event.node.id]&.step_states || []
        )
      end

      def job_annotated(event, node_states, _run_annotations)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: node_state.status, phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: node_state.step_states,
          annotations: node_state.annotations.merge(event.annotations)
        )
      end

      def step_started(event, node_states, _run_annotations)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: node_state.status, phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: start_step_state(node_states[event.node.id]&.step_states, event)
        )
      end

      def step_finished(event, node_states, _run_annotations)
        node_state = node_states[event.node.id]
        node_states[event.node.id] = NodeState.for(
          event.node,
          status: node_state.status, phase: node_state.phase,
          timestamps: timestamps_for(node_state),
          step_states: update_step_states(node_states[event.node.id]&.step_states, event)
        )
      end

      def pipeline_annotated(event, _node_states, run_annotations)
        run_annotations.merge!(event.annotations)
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

    State = Data.define(:pipeline, :nodes, :annotations) do
      def self.empty(pipeline)
        states = {}
        nodes = Pipeline::Reducer.lower(pipeline)
        nodes.each do |node|
          states[node.id] = empty_node_state_for(node)
        end

        new(pipeline:, nodes: states, annotations: {})
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
        StateReducer.new.handle_event(event, new_states, updated_annotations)
        State[pipeline:, nodes: new_states, annotations: updated_annotations]
      end
    end
  end
end
