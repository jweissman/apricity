# frozen_string_literal: true

module Apricity
  module Model
    Pipeline = Data.define(:name, :on, :actions, :path) do
      def initialize(name:, on: {}, actions: [], path: nil)
        super
      end

      def slug = name.downcase.gsub(/\s+/, "-")
      def action(name) = actions.find { |action| action.name == name }

      def total_steps = actions.sum { |action| action.jobs.sum { |job| job.steps.size } }

      def self.from_yaml(yaml_data, path: nil)
        data = YAML.safe_load(yaml_data, symbolize_names: true)
        actions = Apricity::Pipeline::Parser.parse_actions(data, path:)
        new(name: data[:name] || "default", on: data[:on], actions:, path:)
      end

      def self.from_file(file_path)
        # If we are given a directory, look for 'apricity.yaml'
        file_path = File.join(file_path, "apricity.yaml") if File.directory?(file_path)

        from_yaml(File.read(file_path), path: file_path)
      end
    end
  end
end
