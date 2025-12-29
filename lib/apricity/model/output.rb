# frozen_string_literal: true

module Apricity
  module Model
    Output = Data.define(:key, :type) do # Artifact or Value
      def initialize(key:, type:)
        super
        raise ArgumentError, "type must be :artifact or :value" unless %i[artifact value].include?(type)
      end
    end
  end
end
