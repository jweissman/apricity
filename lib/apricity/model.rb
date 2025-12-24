# frozen_string_literal: true

module Apricity
  module Model
    Streams = Data.define(:stdout, :stderr)
    Location = Data.define(:node, :step)

    StepOutcome = Data.define(
      :action, :job, :step,
      :status, :message,
      :container, :script,
      :stdout, :stderr
    ) do
      def successful? = status == "success"
      def failed? = status == "failure"
      def skipped? = status == "skipped"

      def inspect
        "#<StepOutcome #{action}/#{job}:#{step} - #{status} - #{message}>"
      end

      def self.from_location(location, status:, streams:, message: nil)
        new(
          action: location.node.action_name, job: location.node.job_name, step: location.step.name,
          status:, message:,
          container: location.node.runs_on,
          script: location.step.run.lines.join("\n"),
          stdout: streams.stdout, stderr: streams.stderr
          # outputs:
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

      def self.success(node, step, stdout:, stderr:)
        from_location(Location[node:, step:], status: "success", streams: Streams[stdout, stderr],
                                              message: "ok")
      end
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
        super
      end
    end
    Action = Data.define(:name, :jobs)
    Pipeline = Data.define(:name, :on, :actions) do
      def total_steps = actions.sum { |action| action.jobs.sum { |job| job.steps.size } }

      def self.from_yaml(yaml_data)
        data = YAML.safe_load(yaml_data, symbolize_names: true)
        actions = PipelineParser.parse_actions(data)
        new(data[:name] || "default", data[:on], actions)
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

        def to_job
          Model::Job[
                  name:,
                  steps:,
                  runs_on:,
                  inputs:,
                  outputs:,
                  conditions:,
                  needs:
                ]
        end
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
