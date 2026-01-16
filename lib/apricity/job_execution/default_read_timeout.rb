# frozen_string_literal: true

module Apricity
  module JobExecution
    DEFAULT_READ_TIMEOUT = ENV.fetch("APRICITY_DOCKER_READ_TIMEOUT", 300).to_i.freeze
  end
end
