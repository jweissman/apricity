# frozen_string_literal: true

module Apricity
  module JobExecution
    # Mange working directory and host path mapping
    Workspace = Data.define(:target, :host_path) do
      def self.resolve(bind_mounts, resolver:)
        candidates =
          bind_mounts.select do |m|
            next false unless m.type == :bind

            resolved = m.source
            resolved.start_with?(resolver.root + File::SEPARATOR)
          end
        mount = candidates.one? ? candidates.first : nil

        return nil unless mount

        host_path = mount.source
        new(target: mount.target, host_path:)
      end
    end
  end
end
