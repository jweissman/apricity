# frozen_string_literal: true

module Apricity
  # Models for conditions and their evaluation
  module Conditions
    Success = Data.define(:node_id) do
      def to_s = "Success(#{node_id})"
      def evaluate?(context) = context.node_status(node_id) == :success
    end
    Equals = Data.define(:key, :value) do
      def to_s = "Equals(#{key} == #{value})"
      def evaluate?(context) = context.value(key) == value
    end
    Exists = Data.define(:artifact_key) do
      def to_s = "Exists(#{artifact_key})"
      def evaluate?(context) = !context.artifact(artifact_key).nil?
    end
    All = Data.define(:conds) do
      def to_s = "All(#{conds.map(&:to_s).join(", ")})"
      def evaluate?(context) = conds.all? { |c| c.evaluate(context) }
    end
    Any = Data.define(:conds) do
      def to_s = "Any(#{conds.map(&:to_s).join(", ")})"
      def evaluate?(context) = conds.any? { |c| c.evaluate(context) }
    end

    # Evaluate a condition against the given execution context
    def self.evaluate(cond, context)
      ret = cond.evaluate?(context)
      Console.info(self, "evaluate_condition", condition: cond.to_s, context:, result: ret)
      ret
    end
  end
end
