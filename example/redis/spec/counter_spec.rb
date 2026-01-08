# frozen_string_literal: true
require "counter"

RSpec.describe Counter do
  subject(:counter) { described_class.new(redis, "test_counter") }
  let(:url) { ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
  let(:redis) { Redis.new(url:) }

  before do
    redis.flushdb # Clear the test database
  end

  after do
    redis.close
  end

  it "increments and retrieves the counter value from Redis" do
    expect(counter.value).to eq(0)

    counter.increment
    counter.increment

    expect(counter.value).to eq(2)
  end
end