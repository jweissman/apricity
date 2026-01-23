# frozen_string_literal: true

require_relative "action_definition"

module Apricity
  module Actions
    # Caching action definition
    class Cache < ActionDefinition
      # Helper methods for digest calculation
      module DigestHelper
        def md5_command(checksum_file) = <<~SH
          ruby -e 'require "digest"; puts Digest::SHA256.file("#{checksum_file}").hexdigest'
        SH

        def digest!(checksum_file:, container:)
          stdout, _stderr, _code = container.exec(["sh", "-c", md5_command(checksum_file)])
          stdout[0].strip
        end
      end

      module Constants
        CACHE_ROOT = ENV.fetch("APRICITY_CACHE_ROOT") do
          File.expand_path(File.join(Dir.home, ".apricity", "cache"))
        end.freeze
      end

      attr_reader :job_id, :step_id, :job_name

      def initialize(job_id: nil, step_id: nil, options: {})
        super(org: "apricity", name: "cache", version: "v0", options:, job_id:, step_id:)
      end

      def self.set_cache_key(key, checksum, group: "default")
        @cache_keys ||= {}
        @cache_keys[group] ||= {}
        @cache_keys[group][key] = checksum
      end

      # = @cache_keys&.key?(key)
      def self.cache_key?(key, group: "default")
        @cache_keys&.dig(group, key)
      end

      def self.get_cache_key(key, group: "default")
        # @cache_keys[key] if @cache_keys
        @cache_keys&.dig(group, key)
      end

      def before_execute(meta:)
        # log "Starting cache action with options: #{options.inspect}"
        checksum = digest(meta:, options:)
        cache_dir = File.join(Constants::CACHE_ROOT, options[:key], checksum)
        perform_cache_action(options:, cache_dir:, meta:)
        # log "Cache action completed."
      rescue StandardError => e
        log "Cache action failed: #{e.class}: #{e.message}"
        log e.backtrace.join("\n")

        raise e
      end

      private

      def log(message) = warn "[Cache] #{message}"

      def digest(meta:, options:)
        return self.class.get_cache_key(options[:key], group: meta.run_id) if self.class.cache_key?(options[:key],
                                                                                                    group: meta.run_id)

        checksum = DigestHelper.digest!(checksum_file: options[:checksum_file], container: meta.container)
        self.class.set_cache_key(options[:key], checksum, group: meta.run_id)
        checksum
      end

      # def digest!(checksum_file:, container:)
      #   stdout, _stderr, _code = container.exec(["sh", "-c", md5_command(checksum_file)])
      #   stdout[0].strip
      # end

      def perform_cache_action(options:, cache_dir:, meta:)
        if options[:perform_restore]
          restore_cache(container: meta.container, working_dir: meta.working_dir, cache_dir:,
                        paths: options[:paths] || [])
        elsif options[:perform_save]
          save_cache(container: meta.container, working_dir: meta.working_dir, cache_dir:,
                     paths: options[:paths] || [])
        else
          raise "Cache action must specify either :perform_restore or :perform_save option"
        end
      end

      def cache_hit?(cache_dir:, paths:)
        expected = paths.map { |p| File.join(cache_dir, "#{p}.tar") }

        if expected.all? { |f| File.exist?(f) && File.size?(f) }
          log "Cache hit -- cache already populated: #{cache_dir}"
          return true
        end

        log "Cache miss -- cache not found or incomplete: #{cache_dir}"
        false
      end

      def save_cache(container:, working_dir:, cache_dir:, paths:)
        return if cache_hit?(cache_dir:, paths:)

        # log "Cache miss/incomplete cache: #{cache_dir}"
        FileUtils.mkdir_p(cache_dir)

        FileUtils.mkdir_p(cache_dir)
        paths.each do |path|
          log "Saving cache path #{path} from #{working_dir}/#{path}"
          save_cache_path(container:, working_dir:, cache_dir:, path:)
        end
      end

      def save_cache_path(container:, working_dir:, cache_dir:, path:)
        tar_path = File.join(cache_dir, "#{path}.tar")
        FileUtils.mkdir_p(File.dirname(tar_path))
        File.open(tar_path, "wb") do |f|
          _stdout, _stderr, code = container.exec(
            ["/bin/sh", "-lc", %(cd "#{working_dir}" && tar -cf - "#{path}")]
          ) do |stream, chunk|
            f.write(chunk) if stream == :stdout
          end
          raise "tar failed for #{path}" unless code.zero?
        end
      end

      def restore_cache(container:, working_dir:, cache_dir:, paths:)
        unless Dir.exist?(cache_dir)
          log "Cache directory #{cache_dir} does not exist; skipping restore."
          return
        end

        paths.each do |path|
          restore_cache_path(container:, working_dir:, cache_dir:, path:)
        end
      end

      # rubocop:disable Metrics/MethodLength
      def restore_cache_path(container:, working_dir:, cache_dir:, path:)
        tar_path = File.join(cache_dir, "#{path}.tar")
        return unless File.exist?(tar_path)

        tar_name = File.basename(tar_path)          # "bundle.tar"
        tmp_tar  = File.join("/tmp", tar_name)      # "/tmp/bundle.tar"

        file_size = File.size(tar_path)
        log "Restoring cache path #{path} to #{working_dir}/#{path} (#{file_size} bytes)"

        container.archive_in([tar_path], "/tmp")

        _out, err, code = container.exec(
          ["/bin/sh", "-lc", %(cd "#{working_dir}" && tar -xf "#{tmp_tar}")]
        )
        raise "cache restore tar failed for #{path}: #{err.join}" unless code.zero?
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
