# frozen_string_literal: true

module Apricity
  module Model
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
          action: location.node.action_name, job: location.node.job_name, step: location.step&.name,
          status:, message:,
          container: location.node.runs_on,
          script: location.step&.run&.source,
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
  end
end
