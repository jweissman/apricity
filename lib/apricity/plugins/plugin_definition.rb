# frozen_string_literal: true

module Apricity
  module Plugins
    # A _plugin_ observes job execution and can perform custom actions
    PluginDefinition = Data.define(:org, :name, :version) do
      def register = PluginRegistry.instance.register(self)

      def to_s = "#{name}:#{version}"

      def handle_event(event, context:, emitter:, options:)
        Console.info(self, "plugin_event", plugin: to_s, event_type: event.type, node_id: context.node.id)
        public_send(event.type, context:, emitter:, options:) if respond_to?(event.type, true)
      end
    end
  end
end
