# frozen_string_literal: true

module Apricity
  module JobExecution
    Context = Data.define(
      :nodes,       # job_id => :success | :failure | :skipped
      :artifacts,   # key => value
      :values,      # key => value,
      :dependencies # job_id => [dependent_job_ids]
    ) do
      def self.empty = Context.new({}, {}, {}, {})
      def artifact(key)        = artifacts[key]
      def value(key)           = values[key]
      def node_status(node_id) = nodes[node_id]
    end
  end
end
