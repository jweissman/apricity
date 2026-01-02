# frozen_string_literal: true

module Apricity
  module JobExecution
    # This is poorly named, it should move to PipelineStateContext or similar
    Context = Data.define(
      :pipeline_name, # string
      :nodes,         # job_id => :success | :failure | :skipped
      :artifacts,     # key => value
      :values,        # key => value,
      :dependencies   # job_id => [dependent_job_ids]
    ) do
      def self.empty = Context.new("default", {}, {}, {}, {})
      def artifact(key)        = artifacts[key]
      def value(key)           = values[key]
      def node_status(node_id) = nodes[node_id]
    end
  end
end
