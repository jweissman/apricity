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

      def self.from_yaml(data, path: nil)
        actions = Apricity::Pipeline::Parser.parse_actions(data, path:)
        new(name: data[:name] || "default", on: data[:on], actions:, path:)
      end

      def self.from_file(file_path)
        file_path = File.join(file_path, "apricity.yaml") if File.directory?(file_path)
        yaml_erb_content = File.read(file_path)
        erb_template = ERB.new(yaml_erb_content)
        interpolated_yaml_string = erb_template.result(binding)
        data = YAML.safe_load(interpolated_yaml_string, symbolize_names: true)

        from_yaml(data, path: file_path)
      end
    end
  end
end
