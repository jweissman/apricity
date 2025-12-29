# frozen_string_literal: true

module Apricity
  module JobExecution
    # Events emitted during job execution
    module Events
      def self.prefix(event)
        "#{event.node.action_name}##{event.node.job_name}"
      end

      JobStarted = Data.define(:node, :started_at) do
        def type = :job_started
        def pretty = "started job #{node.job_name}"
      end
      JobSkipped = Data.define(:node, :reason, :skipped_at) do
        def type = :job_skipped
        def pretty = "skipped #{node.job_name} due to #{reason}"
      end
      JobFinished = Data.define(:node, :status, :finished_at, :exception) do
        def initialize(node:, status:, finished_at:, exception: nil)
          super
        end

        def type = :job_finished

        def pretty
          if exception
            "finished job with status #{status} due to exception: #{exception.message}"
          else
            "finished job with status #{status}"
          end
        end
      end

      StepStarted = Data.define(:node, :step, :started_at) do
        def type = :step_started
        def pretty = "started step #{step.name}"
      end
      StepFinished = Data.define(:node, :step, :status, :finished_at) do
        def type = :step_finished
        def pretty = "finished step #{step.name} with status #{status}"
      end

      # No timestamp needed for chunk events as they are numerous
      StdoutChunk = Data.define(:node, :step, :chunk) do
        def type = :stdout_chunk
        def pretty = "(stdout chunk from step #{step.name})"
      end
      StderrChunk = Data.define(:node, :step, :chunk) do
        def type = :stderr_chunk
        def pretty = "(stderr chunk from step #{step.name})"
      end
    end
  end
end
