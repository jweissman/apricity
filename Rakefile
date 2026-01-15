# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "reek/rake/task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/**/*_spec.rb"
  t.rspec_opts = "--color --format documentation --tag ~dind"
end
RuboCop::RakeTask.new
Reek::Rake::Task.new do |t|
  t.fail_on_error = false
end

task default: %i[spec rubocop reek]
