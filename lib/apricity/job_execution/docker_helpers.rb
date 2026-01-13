# frozen_string_literal: true

module Apricity
  module JobExecution
    # Common helpers for docker
    module DockerHelpers
      def self.dind? = File.exist?("/.dockerenv")
    end
  end
end
