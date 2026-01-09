# frozen_string_literal: true

module Apricity
  module Plugins
    # A _plugin_ observes job execution and can perform custom actions
    # PluginDefinition = Data.define(:org, :name, :version) do
    PluginDefinition = Struct.new(:org, :name, :version, :job_id, :options, keyword_init: true) do
      def key = [org, name, version, options].join("/").gsub(/\s+/, "-")

      def to_s = "#{name}:#{version}"

      def handle(event, context:, emitter:)
        handle_event(event, context:, emitter:, options:)
      end

      private

      def handle_event(event, context:, emitter:, options:)
        # Console.info(self, "plugin_event", plugin: to_s, event_type: event.type, node_id: (
        #   context.node.id if context.respond_to?(:node) && context.node
        # ))
        public_send(event.type, context:, emitter:, options:, event:) if respond_to?(event.type, true)
      end
    end
  end
end
