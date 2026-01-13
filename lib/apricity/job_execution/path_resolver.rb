# frozen_string_literal: true

module Apricity
  module JobExecution
    # Tiny helper to resolve paths relative to a root
    class PathResolver
      attr_reader :root

      def initialize(root:)
        @root = root
      end

      def resolve(path)
        return path if path.start_with?("/")

        warn "!!! Resolving relative path #{path.inspect} against root #{@root.inspect}"
        File.expand_path(path, @root)
      end
    end
  end
end
