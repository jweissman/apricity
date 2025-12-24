# frozen_string_literal: true

module Apricity
  # Global configuration for Apricity
  class Configuration
    attr_reader :bind_mounts, :output_sink

    def initialize
      @bind_mounts = []
      @output_sink = NullOutputSink.new
    end

    def self.instance
      @instance ||= Configuration.new
    end
  end
end
