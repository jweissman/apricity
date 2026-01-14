# frozen_string_literal: true

module Apricity
  module Model
    module Builders
      # Job builder DSL
      class JobBuilder
        attr_reader :name, :steps, :runs_on, :inputs, :outputs, :conditions, :needs, :strategy

        def initialize(runs_on:, name: nil)
          @name = name
          @runs_on = runs_on
          @steps = []
          @inputs = []
          @outputs = []
          @conditions = []
          @needs = []
          @strategy = Strategy.empty
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

        def matrix(matrix = {})
          @strategy = Strategy.new(matrix:)
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
                  needs:,
                  strategy:
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
