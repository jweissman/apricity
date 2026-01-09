# frozen_string_literal: true

require_relative "action_definition"

module Apricity
  module Actions
    # Checkout action definition
    class Checkout < ActionDefinition
      attr_reader :job_id, :step_id, :job_name

      def initialize(job_id: nil, step_id: nil, options: {})
        super(org: "apricity", name: "checkout", version: "v0", options:, job_id:, step_id:)
      end

      def to_shell = git_checkout(url: clone_url, branch:, target_dir:)

      private

      def git_checkout(url:, branch: "main", target_dir: ".")
        <<~SH
          git config --global --add safe.directory #{target_dir}
          git -c http.sslVerify=true \
              -c credential.helper= \
              clone --depth=1 \
              --branch #{branch} \
              #{url} #{target_dir}
        SH
        # <<~BASH
        #   ls -latr #{target_dir}
        #   git clone \
        #     --branch #{branch} \
        #     #{url} #{target_dir}
        # BASH
        # "git clone \
        #   --branch #{branch} \
        #   #{url} #{target_dir}"
      end

      def clone_url = options[:repository] || raise("Missing 'repository' option for checkout action")
      def branch = options[:branch] || "main"
      def target_dir = "/work"
    end
  end
end
