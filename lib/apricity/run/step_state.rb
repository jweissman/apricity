# frozen_string_literal: true

module Apricity
  module Run
    StepState = Data.define(:name, :job, :status, :started_at, :finished_at) do
      def duration_seconds = started_at ? ((finished_at || Time.now) - started_at).round(2) : nil
    end
  end
end
