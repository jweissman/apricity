# frozen_string_literal: true

module Apricity
  module Model
    Job = Data.define(
      :name, :steps, :runs_on,
      :inputs, :outputs, :conditions, :needs, :mounts, :plugins, :strategy, :services
    ) do
      # Initializer to provide default empty arrays/hashes
      # rubocop:disable Metrics/ParameterLists
      def initialize(
        name:,
        runs_on:,
        steps:,
        conditions: [],
        inputs: [],
        mounts: [],
        needs: [],
        outputs: [],
        plugins: [],
        services: [],
        strategy: nil
      )
        super
      end
      # rubocop:enable Metrics/ParameterLists

      def step(name) = steps.find { |step| step.name == name }
    end
  end
end
