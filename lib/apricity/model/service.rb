# frozen_string_literal: true

module Apricity
  module Model
    Service = Data.define(:name, :image, :ports, :env_vars, :volumes) do
      # Initializer to provide default empty arrays/hashes
      def initialize(
        name:,
        image:,
        ports: [],
        env_vars: {},
        volumes: []
      )
        super
      end
    end
  end
end
