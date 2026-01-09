# frozen_string_literal: true

module Apricity
  # Global configuration for Apricity
  class Configuration
    attr_reader :bind_mounts, :output_sink, :concurrency_enabled

    def initialize
      @bind_mounts = []
      @output_sink = NullOutputSink.new
      @concurrency_enabled = true
    end

    def concurrency_enabled? = @concurrency_enabled

    def self.instance
      @instance ||= Configuration.new
    end
  end
end
