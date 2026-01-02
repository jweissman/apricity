# frozen_string_literal: true

module Apricity
  module Model
    Plugin = Data.define(:name, :org, :version, :with) do
      def to_s = "#{org}/#{name}:#{version}"

      def plugin_class = Apricity::Plugins::PluginRegistry.instance.get_plugin(self)
    end
  end
end
