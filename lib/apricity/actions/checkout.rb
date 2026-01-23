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

      def to_shell = git_checkout(url: clone_url, branch: options[:ref], target_dir:)

      private

      def git_checkout(url:, branch: "main", target_dir: ".")
        <<~SH
          export GIT_TERMINAL_PROMPT=0
          git config --global --add safe.directory #{target_dir}
          git -c http.sslVerify=true \
              -c credential.helper= \
              clone --depth=1 \
              --single-branch \
              --no-tags \
              --filter=blob:none \
              --branch #{branch} \
              #{url} #{target_dir}

          # parse git sha
          cd #{target_dir}
          GIT_SHA=$(git rev-parse HEAD)
          echo "Checked out branch '#{branch}' at commit $GIT_SHA"
          echo "::set-run-meta git-sha=$GIT_SHA"

          cd -
        SH
      end

      def clone_url = options[:repository] || raise("Missing 'repository' option for checkout action")
      def branch = options[:branch] || "main"
      def target_dir = "/work"
    end
  end
end
