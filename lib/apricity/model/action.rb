# frozen_string_literal: true

module Apricity
  module Model
    Action = Data.define(:name, :jobs) do
      def job(name) = jobs.find { |job| job.name == name }
    end
  end
end
