# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  coverage_dir "#{ENV.fetch('APRICITY_ARTIFACTS', '.')}/coverage"
end

require_relative "../lib/greeter"

RSpec.describe Greeter do
  subject(:greeter) { described_class.new }

  it "says hello" do
    expect(greeter.greet).to eq("Hello, World!")
  end
end
