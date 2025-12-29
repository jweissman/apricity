# frozen_string_literal: true

module Apricity
  module Pipeline
    # Parses high-level pipeline definitions from YAML or Hash structures
    #
    # Example YAML:
    #   build:
    #     jobs:
    #       - build_and_test:
    #           runs-on: ruby:3.4
    #           name: Build and Test Checked-out Apricity
    #           mounts:
    #             - source: .
    #               target: /app
    #               type: bind
    #           steps:
    #             - name: Install dependencies
    #               run: |
    #                 bundle install
    #             - name: Run Apricity Specs
    #               run: |
    #                 bundle exec rspec spec/lib/apricity_spec.rb
    class Parser
      include Apricity::Model

      def self.parse_actions(data = {})
        data[:actions].map do |action_name, action_data|
          jobs = action_data[:jobs].map do |job_entry|
            parse_job(job_entry)
          end
          Action[name: action_name || action_data[:name], jobs:]
        end
      end

      def self.parse_job(job_entry)
        job_name, job_data = job_entry.first
        Job[
          name: job_name, steps: parse_steps(job_data[:steps]),
          runs_on: Container[*job_data[:"runs-on"].split(":", 2)],
          **parse_input_output(job_data),
          conditions: parse_conditions(job_data[:conditions]),
          needs: job_data[:needs] || [],
          mounts: parse_mounts(job_data[:mounts]),
          plugins: parse_plugins(job_data[:plugins])
        ]
      end

      def self.parse_input_output(job_data)
        { inputs: parse_inputs(job_data[:inputs]), outputs: parse_outputs(job_data[:outputs]) }
      end

      def self.parse_steps(step_data_array = [])
        step_data_array.map do |step_data|
          Step[name: step_data[:name], run: Script[
            source: normalize_script(step_data[:run])
          ]]
        end
      end

      def self.normalize_script(raw)
        lines = raw.lines.map(&:rstrip)

        joined = +""
        lines.each do |line|
          if line.end_with?("\\")
            joined << line.strip.chomp("\\") << ""
          else
            joined << line.strip << "\n"
          end
        end

        joined.strip
      end

      def self.parse_inputs(input_data_array = [])
        input_data_array&.map do |input_data|
          Input[input_data[:key], input_data[:type].to_sym]
        end || []
      end

      def self.parse_outputs(output_data_array = [])
        output_data_array&.map do |output_data|
          type = output_data[:type].to_sym
          raise "Unknown output type #{output_data[:type]}" unless %i[artifact value].include?(type)

          Output[output_data[:key], type]
        end || []
      end

      def self.parse_conditions(condition_data_array = [])
        condition_data_array&.map do |cond|
          Condition[cond[:expression]]
        end || []
      end

      def self.parse_mounts(mount_data_array = [])
        mount_data_array&.map do |mount_data|
          Mount[mount_data[:source], mount_data[:target], mount_data[:type].to_sym]
        end || []
      end

      def self.parse_plugins(plugin_data_array = [])
        plugin_data_array&.map do |plugin|
          uses, with_options = plugin.values_at(:uses, :with)
          org, name_version = uses.split("/", 2)
          name, version = name_version.split(":", 2)
          version ||= "latest"
          Model::Plugin[org:, name:, version:, with: with_options || {}]
        end
      end
    end
  end
end
