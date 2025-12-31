# frozen_string_literal: true

module Apricity
  module Run
    NodeState = Data.define(
      :id, :name, :status, :phase, :started_at, :finished_at, :step_states, :annotations
    ) do
      # rubocop:disable Metrics/ParameterLists
      def self.for(node, status:, phase:, timestamps:, step_states:, annotations: {}) = new(
        id: node.id, name: node.job_name,
        status:, phase:,
        started_at: timestamps.started_at,
        finished_at: timestamps.finished_at,
        step_states:,
        annotations:
      )
      # rubocop:enable Metrics/ParameterLists

      def duration_seconds = (finished_at - started_at).round(2)
    end
  end
end
