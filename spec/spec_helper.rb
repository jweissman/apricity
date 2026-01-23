# frozen_string_literal: true

# require "debug"
require "simplecov"
# require "simplecov_json_formatter"
# SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
SimpleCov.command_name "rspec-shard-#{ENV["MATRIX_SHARD"]}" if ENV["MATRIX_SHARD"]
SimpleCov.start do
  puts "Starting SimpleCov for Apricity SimplecovReporter Plugin"
  coverage_dir "#{ENV.fetch("APRICITY_ARTIFACTS", ".")}/coverage"
end

# require "debug"

require "apricity"
require "apricity/model/builders"
require_relative "support/successful_pipeline"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # focus filter
  config.filter_run_when_matching :focus
end
