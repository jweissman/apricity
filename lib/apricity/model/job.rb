# frozen_string_literal: true

module Apricity
  module Model
    Job = Data.define(:name, :steps, :runs_on, :inputs, :outputs, :conditions, :needs, :mounts, :plugins) do
      # Initializer to provide default empty arrays/hashes
      # rubocop:disable Metrics/ParameterLists
      def initialize(
        name:,
        steps:,
        runs_on:,
        inputs: [],
        outputs: [],
        conditions: [],
        needs: [],
        mounts: [],
        plugins: []
      )
        super
      end
      # rubocop:enable Metrics/ParameterLists

      def step(name) = steps.find { |step| step.name == name }
    end
  end
end
