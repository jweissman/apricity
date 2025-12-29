# frozen_string_literal: true

module Apricity
  module Model
    Plugin = Data.define(:name, :org, :version, :with) do
      def to_s = "#{org}/#{name}:#{version}"

      def handle(event, context:, emitter:)
        Apricity::Plugins::PluginRegistry.instance
                                         .get_plugin(self)
                                         .handle_event(event, context:, emitter:, options: with)
      end
    end
  end
end
