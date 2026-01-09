# frozen_string_literal: true

require_relative "checkout"

module Apricity
  module Actions
    # Registry for managing available actions
    class ActionRegistry
      def initialize
        @actions = {}
      end

      def register_builtin_actions
        register Checkout
      end

      def register(action_def)
        action = action_def.new
        key = "#{action.org}/#{action.name}:#{action.version}"
        @actions[key] = action_def
        Console.info(self, "action_registered", action: key)
      end

      def fetch(org, name, version)
        key = "#{org}/#{name}:#{version}"
        action = @actions[key]
        unless action
          Console.error(self, "action_not_found", action: key)
          raise "Action not found: #{key}"
        end
        action
      end

      def latest_version(org:, name:)
        @actions.keys.select { |k| k.start_with?("#{org}/#{name}:") }
                .map { |k| k.split(":").last }
                .max
      end

      # def version(action)
      #   if action.version == "latest"
      #     latest_version(org: action.org, name: action.name)
      #   else
      #     action.version
      #   end
      # end

      # def get_action(action) = fetch(action.org, action.name, version(action))

      def resolve(action_key)
        org_name, version = action_key.split("@")
        org, name = org_name.split("/")
        version ||= "latest"
        fetch(org, name, version)
        # action_def = Apricity::Actions::ActionDefinition.new(org:, name:, version:)
        # action = OpenStruct.new(org:, name:, version:)
        # get_action(action_def)
      end

      def self.instance = @instance ||= new
    end
  end
end
