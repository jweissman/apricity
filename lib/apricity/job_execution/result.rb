# frozen_string_literal: true

module Apricity
  module JobExecution
    Result = Data.define(:outcomes, :outputs) do
      def passed? = outcomes.all?(&:successful?)
      def failed? = outcomes.any?(&:failed?)
    end
  end
end
