# frozen_string_literal: true

module Apricity
  module Pipeline
    # Helper methods for parsing
    module ParsingHelpers
      def normalize_script(raw)
        lines = raw&.lines&.map(&:rstrip) || []

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
    end

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
      extend ParsingHelpers

      def self.parse_actions(data = {}, path: nil)
        data[:actions].map do |action_name, action_data|
          jobs = action_data[:jobs].map do |job_entry|
            parse_job(job_entry, path:)
          end
          Action[name: action_name || action_data[:name], jobs:]
        end
      end

      def self.parse_job(job_entry, path: nil)
        job_name, job_data = job_entry.first
        Job[
          name: job_name, steps: parse_steps(job_data[:steps]),
          runs_on: parse_container(job_data[:"runs-on"]),
          **parse_job_extras(job_data, path:)
        ]
      end

      def self.parse_job_extras(job_data, path: nil)
        {
          **parse_input_output(job_data), **parse_needs_and_conditions(job_data),
          mounts: parse_mounts(job_data[:mounts], path:),
          plugins: parse_plugins(job_data[:plugins]),
          strategy: parse_strategy(job_data[:strategy]),
          services: parse_services(job_data[:services]),
          env_vars: job_data[:env] || {}
        }
      end

      def self.parse_needs_and_conditions(job_data)
        conditions = parse_conditions(job_data[:conditions])
        needs = job_data[:needs] || []
        { conditions:, needs: }
      end

      def self.parse_strategy(strategy_data)
        return Strategy.empty unless strategy_data

        Model::Strategy.new(matrix: strategy_data[:matrix] || {})
      end

      def self.parse_container(runs_on_data)
        return nil unless runs_on_data

        Container[*runs_on_data.split(":", 2)]
      end

      def self.parse_input_output(job_data)
        { inputs: parse_inputs(job_data[:inputs]), outputs: parse_outputs(job_data[:outputs]) }
      end

      def self.parse_steps(step_data_array = [])
        step_data_array.map do |step_data|
          Step[
            name: step_data[:name], uses: step_data[:uses], with: step_data[:with],
            run: Script[source: normalize_script(step_data[:run])]
          ]
        end
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

      def self.parse_mounts(mount_data_array = [], path:)
        mount_data_array&.map do |mount_data|
          source = if mount_data[:source] == "." && path
                     File.dirname(path)
                   else
                     mount_data[:source]
                   end

          Mount[source, mount_data[:target], mount_data[:type].to_sym]
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

      def self.parse_services(service_map = {})
        service_map&.map do |service_name, service_data|
          Model::Service[
            name: service_name.to_s,
            image: service_data[:image],
            ports: service_data[:ports] || [],
            env_vars: service_data[:env] || {}
          ]
        end || []
      end
    end
  end
end
