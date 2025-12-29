# frozen_string_literal: true

module Apricity
  module Model
    Script = Data.define(:source) do
      def source_lines = source.lines.map(&:chomp)
    end
  end
end
