# frozen_string_literal: true

module Apricity
  module Model
    Strategy = Data.define(:matrix) do
      def self.empty = Strategy.new({})
    end
  end
end
