# frozen_string_literal: true

module Apricity
  # Base class for output sinks
  class OutputSink
    def call(event) = handle(event.type, event)

    protected

    def handle(type, data)
      puts "Unhandled output sink event: #{type} - #{data.inspect}"
      raise NotImplementedError, "OutputSink subclasses must implement handle"
    end
  end

  # A no-op output sink that discards all events
  class NullOutputSink < OutputSink
    def handle(_type, _data); end
  end
end
