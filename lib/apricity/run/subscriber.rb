# frozen_string_literal: true

module Apricity
  module Run
    Subscriber = Data.define(:queue) do
      def push(event) = queue << event
    end
  end
end
