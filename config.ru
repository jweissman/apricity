# frozen_string_literal: true

ENV["RACK_ENV"] ||= "production"

require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "production"))

$stdout.sync = true
$stderr.sync = true

require_relative "lib/apricity"
require_relative "lib/apricity/web/april"

# Load default plugins and actions
Apricity.register_default_plugins
Apricity.register_default_actions

# Start webserver
run Apricity::Web::April
