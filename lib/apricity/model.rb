# frozen_string_literal: true

module Apricity
  module Model
    Streams = Data.define(:stdout, :stderr)
    Location = Data.define(:node, :step)

    Event = Data.define(
      :action, :job, :step,
      :status, :message,
      :container, :script,
      :stdout, :stderr,
      :outputs
      # :artifacts
    ) do
      def successful? = status == "success"
      def failed? = status == "failure"
      def skipped? = status == "skipped"

      def inspect = "#<Event #{action}/#{job}:#{step} - #{status} - #{message}>"

      def self.from_location(location, status:, streams:, outputs: {}, message: nil)
        new(
          action: location.node.action_name, job: location.node.job_name, step: location.step.name,
          status:, message:,
          container: location.node.runs_on,
          script: location.step.run.lines.join("\n"),
          stdout: streams.stdout, stderr: streams.stderr, outputs:
        )
      end

      def self.skipped(node, step, reason:)
        from_location(
          Location[node:, step:],
          status: "skipped",
          streams: Streams["", ""],
          message: "Skipped due to #{reason}"
        )
      end

      def self.failure(node, step, stdout:, stderr:, exception: nil)
        from_location(
          Location[node:, step:],
          status: "failure",
          streams: Streams[stdout, stderr],
          message: exception&.message || "An error occurred"
        )
      end

      def self.success(node, step, stdout:, stderr:, outputs: {})
        from_location(Location[node:, step:], status: "success", streams: Streams[stdout, stderr], outputs:,
                                              message: "ok")
      end

      # def self.warning(node, step, stdout:, stderr:, outputs: {}, message: nil)
      #   from_location(Location[node:, step:],
      #                 status: "warning", message:,
      #                 streams: Streams[stdout, stderr], outputs:)
      # end
    end

    Container = Data.define(:name, :version) do
      def to_s = "#{name}:#{version}"
    end
    Condition = Data.define(:expression)
    Script = Data.define(:lines)
    Environment = Data.define(:variables)
    Step = Data.define(:name, :run)

    Output = Data.define(:key, :type) # Artifact or Value
    Input  = Data.define(:key, :type)
    Mount  = Data.define(:source, :target, :type)
    Job = Data.define(:name, :steps, :runs_on, :inputs, :outputs, :conditions, :needs, :mounts) do
      # Initializer to provide default empty arrays/hashes
      def initialize(name:, steps:, runs_on:, inputs: [], outputs: [], conditions: [], needs: [], mounts: [])
        super(name:, steps:, runs_on:, inputs:, outputs:, conditions:, needs:, mounts:)
      end
    end
    Action = Data.define(:name, :jobs)
    Pipeline = Data.define(:name, :on, :actions) do
      def total_steps = actions.sum { |action| action.jobs.sum { |job| job.steps.size } }

      # Example YAML:
      # actions:
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
      #                 gem install bundler
      #                 bundle install

      #             - name: Run Apricity Specs
      #               run: |
      #                 bundle exec rspec spec/lib/apricity_spec.rb
      def self.from_yaml(yaml_data)
        data = YAML.safe_load(yaml_data, symbolize_names: true)
        puts "Pipeline data: #{data.inspect}"
        actions = data[:actions].map do |action_name, action_data|
          puts "Action data: #{action_data.inspect}"
          jobs = action_data[:jobs].map do |job_entry|
            job_name, job_data = job_entry.first

            puts "Job data: #{job_data.inspect}"
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
          Action[name: action_data[:name], jobs:]
        end
        new(data[:name], data[:on], actions)
      end
    end

    module Builders
      # Job builder DSL
      class JobBuilder
        attr_reader :name, :steps, :runs_on, :inputs, :outputs, :conditions, :needs

        def initialize(runs_on:, name: nil)
          @name = name
          @runs_on = runs_on
          @steps = []
          @inputs = []
          @outputs = []
          @conditions = []
          @needs = []
        end

        def step(name, run:)
          @steps << Model::Step[name:, run:]
          self
        end

        def input(name, type)
          @inputs << Model::Input[name, type]
          self
        end

        def output(name, type)
          @outputs << Model::Output[name, type]
          self
        end

        def demands(*job_names)
          @needs.concat(job_names.flatten)
          self
        end

        def condition(cond)
          @conditions << cond
          self
        end

        def to_job = Model::Job[
          name:,
          steps:,
          runs_on:,
          inputs:,
          outputs:,
          conditions:,
          needs:
        ]
      end

      # Action builder DSL
      class ActionBuilder
        attr_reader :name, :jobs

        def initialize(name:)
          @name = name
          @jobs = []
        end

        def job(name, runs_on:)
          builder = yield JobBuilder.new(name:, runs_on:)
          @jobs << builder.to_job
          self
        end

        def to_action = Model::Action[name:, jobs:]
      end

      # Pipeline builder DSL
      class PipelineBuilder
        attr_reader :name, :actions

        def initialize(name = "default-pipeline")
          @name = name
          @actions = []
        end

        def action(name)
          builder = yield ActionBuilder.new(name:)
          @actions << builder.to_action
          self
        end

        def to_pipeline = Model::Pipeline[name:, on: "push", actions:]

        def self.single_command(container:, command:)
          new("ci").action("single-command") do |act|
            act.job("run-command", runs_on: container) do |job|
              job.step("execute", run: command)
            end
          end.to_pipeline
        end
      end
    end
  end
end
