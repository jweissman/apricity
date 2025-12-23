module Apricity
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
  class PipelineParser
    include Apricity::Model

    def self.parse_actions(data = {})
      data[:actions].map do |action_name, action_data|
        jobs = action_data[:jobs].map do |job_entry|
          job_name, job_data = job_entry.first
          steps = job_data[:steps].map do |step_data|
            Step[name: step_data[:name], run: Script[lines: step_data[:run].lines]]
          end
          inputs = (job_data[:inputs] || []).map do |input_data|
            Input[input_data[:key], input_data[:type].to_sym]
          end
          outputs = (job_data[:outputs] || []).map do |output_data|
            Output[output_data[:key], output_data[:type].to_sym]
          end
          conditions = (job_data[:conditions] || []).map do |cond|
            Condition[cond[:expression]]
          end
          needs = job_data[:needs] || []
          mounts = (job_data[:mounts] || []).map do |mount_data|
            Mount[mount_data[:source], mount_data[:target], mount_data[:type].to_sym]
          end
          Job[
            name: job_name,
            steps:,
            runs_on: Container[*job_data[:"runs-on"].split(":", 2)],
            inputs:,
            outputs:,
            conditions:,
            needs:,
            mounts:
          ]
        end
        Action[name: action_name || action_data[:name], jobs:]
      end
    end
  end
end
