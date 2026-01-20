# frozen_string_literal: true

module Apricity
  module Run
    Result = Data.define(:run, :started_at, :finished_at, :step_states, :final_run_state) do
      def duration_seconds = (finished_at - started_at).round(2)
      def failed_nodes = final_run_state.nodes.values.select { it.status == :failure }
      def retryable? = failed_nodes.any?
      def passed? = failed_nodes.empty?
    end
  end
end
