# frozen_string_literal: false

require "base64"
require "console"
require "docker-api"
require "rubygems/package"
require "securerandom"
require "stringio"
require "yaml"

require_relative "apricity/version"
require_relative "apricity/configuration"
require_relative "apricity/model"
require_relative "apricity/pipeline/graph"
require_relative "apricity/pipeline/reducer"
require_relative "apricity/pipeline/parser"
require_relative "apricity/conditions"
require_relative "apricity/output_sink"
require_relative "apricity/plugins/plugin_registry"
require_relative "apricity/plugins/plugin_definition"
require_relative "apricity/job_execution"
require_relative "apricity/pipeline/runner"
require_relative "apricity/run"

# Apricity: A lightweight CI/CD pipeline runner using Docker containers
#
# Provides pipeline definition, dependency analysis, and job execution
# inside isolated containers.
#
module Apricity
  class Error < StandardError; end
  class JobExecutionError < Error; end

  def self.configure
    yield(Configuration.instance) if block_given?
  end

  def self.register_default_plugins = Plugins::PluginRegistry.instance.register_builtin_plugins
end
