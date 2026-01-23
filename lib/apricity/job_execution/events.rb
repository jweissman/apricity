# frozen_string_literal: true

module Apricity
  module JobExecution
    # Serialize job execution events to JSON
    class EventSerializer
      def self.as_json(event)
        JSON.generate({
          type: event.type,
          message: event.pretty,
          data: payload_json(event),
          at: timestamp(event),
          node: event.respond_to?(:node) ? node_json(event.node) : nil,
          step: event.respond_to?(:step) ? step_json(event.step) : nil
        }.compact)
      end

      def self.timestamp(event)
        time = if event.respond_to?(:started_at)
                 event.started_at
               else
                 event.respond_to?(:finished_at) ? event.finished_at : Time.now
               end
        (time.to_f * 1000).to_i # epoch milliseconds for JS compatibility
      end

      def self.node_json(node)
        return nil unless node

        {
          id: node.id, job_name: node.job_name, action_name: node.action_name
        }
      end

      def self.step_json(step)
        return nil unless step

        {
          name: step.name
        }
      end

      def self.payload_json(event)
        case event.type
        when :job_skipped then { reason: event.reason }
        when :job_started then job_started_payload(event)
        when :job_finished then job_finished_payload(event)
        when :job_annotated, :pipeline_annotated then { annotations: event.annotations }
        when :step_finished then { status: event.status, duration: event.duration_seconds }
        when :stdout_chunk, :stderr_chunk then { chunk: event.chunk }
        else {}
        end
      end

      def self.job_started_payload(event)
        steps = event.node.steps.map { |step| { name: step.name } }
        Console.debug(self, "job_started_payload", node: event.node.id, step_count: steps.size)
        { steps: steps }
      end

      def self.job_finished_payload(event)
        payload = { status: event.status }
        if event.exception
          payload[:exception] = { message: event.exception.message, backtrace: event.exception.backtrace }
        end
        if event.outputs && !event.outputs.empty?
          # Send all outputs - artifacts are paths, other outputs are simple values
          Console.debug(self, "job_finished_payload", outputs: event.outputs)
          payload[:artifacts] = event.outputs
        end
        payload
      end
    end

    # Events emitted during job execution
    module Events
      def self.prefix(event)
        "#{event.node.action_name}##{event.node.job_name}"
      end

      JobStarted = Data.define(:node, :started_at) do
        def type = :job_started
        def pretty = "started job #{node.job_name}"
      end
      JobMetadataUpdated = Data.define(:node, :key, :value, :step) do
        def type = :job_meta_updated
        def pretty = "updated job metadata #{key}=#{value} during step #{step.name}"
      end
      JobSkipped = Data.define(:node, :reason, :skipped_at) do
        def type = :job_skipped
        def pretty = "skipped #{node.job_name} due to #{reason}"
      end
      JobFinished = Data.define(:node, :status, :finished_at, :exception, :outputs) do
        def initialize(node:, status:, finished_at:, exception: nil, outputs: {})
          super
        end

        def type = :job_finished

        def pretty
          if exception
            short_backtrace = exception.backtrace ? exception.backtrace.first(3).join("; ") : "no backtrace"
            "finished job with status #{status} due to exception: #{exception.message} (#{short_backtrace})"
          else
            "finished job with status #{status}"
          end
        end
      end
      JobAnnotated = Data.define(:node, :annotations, :annotated_at) do
        def type = :job_annotated
        def pretty = "annotated job #{node.job_name} with #{annotations.size} annotations"
      end

      StepStarted = Data.define(:node, :step, :started_at) do
        def type = :step_started
        def pretty = "started step #{step.name}"
      end
      StepFinished = Data.define(:node, :step, :status, :started_at, :finished_at) do
        def type = :step_finished
        def pretty = "finished step #{step.name} with status #{status} in #{duration_seconds}s"

        def duration_seconds
          started_at ? ((finished_at || Time.now) - started_at).round(2) : nil
        end
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

      PipelineStarted = Data.define(:pipeline_name, :started_at) do
        def type = :pipeline_started
        def pretty = "pipeline #{pipeline_name} started"
      end

      PipelineFinished = Data.define(:pipeline_name, :finished_at, :outputs_by_node, :status) do
        def type = :pipeline_finished
        def pretty = "pipeline #{pipeline_name} finished"
      end

      PipelineAnnotated = Data.define(:pipeline_name, :annotations, :annotated_at) do
        def type = :pipeline_annotated

        def pretty
          "annotated pipeline #{pipeline_name} with #{annotations.size} annotations: \
          #{annotations.inspect}"
        end
      end
    end
  end
end
