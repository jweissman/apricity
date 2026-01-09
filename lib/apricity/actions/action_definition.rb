# frozen_string_literal: true

module Apricity
  module Actions
    # An _action_ defines a reusable set of jobs that can be included in a job
    ActionDefinition = Struct.new(:org, :name, :version, :job_id, :step_id, :options, keyword_init: true) do
      def key = [org, name, version, options].join("/").gsub(/\s+/, "-")

      def to_s = "#{name}:#{version}"
    end
  end
end
