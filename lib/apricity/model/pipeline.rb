# frozen_string_literal: true

module Apricity
  module Model
    Pipeline = Data.define(:name, :on, :actions) do
      def action(name) = actions.find { |action| action.name == name }

      def total_steps = actions.sum { |action| action.jobs.sum { |job| job.steps.size } }

      def self.from_yaml(yaml_data)
        data = YAML.safe_load(yaml_data, symbolize_names: true)
        actions = Apricity::Pipeline::Parser.parse_actions(data)
        new(data[:name] || "default", data[:on], actions)
      end

      def self.from_file(file_path) = from_yaml File.read(file_path)
    end
  end
end
