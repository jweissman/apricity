# frozen_string_literal: true

module Apricity
  module JobExecution
    # Common helpers for docker
    module DockerHelpers
      def self.dind? = File.exist?("/.dockerenv")

      def self.safe_id(id)
        id.gsub(/[^a-zA-Z0-9_.-]/, "_")
      end
    end
  end
end
