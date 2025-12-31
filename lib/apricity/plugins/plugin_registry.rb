# frozen_string_literal: true

require_relative "junit_reporter"
require_relative "simplecov_reporter"
require_relative "sbom_reporter"
module Apricity
  module Plugins
    # Registry for managing available plugins
    class PluginRegistry
      def initialize
        @plugins = {}
      end

      def register_builtin_plugins
        register(JUnitReporter.new)
        register(SimplecovReporter.new)
        register(SBOMReporter.new)
      end

      def register(plugin_def)
        key = "#{plugin_def.org}/#{plugin_def.name}:#{plugin_def.version}"
        @plugins[key] = plugin_def
        Console.info(self, "plugin_registered", plugin: key)
      end

      def fetch(org, name, version)
        key = "#{org}/#{name}:#{version}"
        plugin = @plugins[key]
        unless plugin
          Console.error(self, "plugin_not_found", plugin: key)
          raise "Plugin not found: #{key}"
        end
        plugin
      end

      def latest_version(org:, name:)
        @plugins.keys.select { |k| k.start_with?("#{org}/#{name}:") }
                .map { |k| k.split(":").last }
                .max
      end

      def version(plugin)
        if plugin.version == "latest"
          latest_version(org: plugin.org, name: plugin.name)
        else
          plugin.version
        end
      end

      def get_plugin(plugin) = fetch(plugin.org, plugin.name, version(plugin))
      def self.instance = @instance ||= PluginRegistry.new
    end
  end
end
