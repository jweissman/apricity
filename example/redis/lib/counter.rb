# frozen_string_literal: true

require "redis"

# A simple example class that implements a counter using Redis.
class Counter
  def initialize(redis_client, key)
    @redis = redis_client
    @key = key
  end

  def increment = @redis.incr(@key)
  def value = @redis.get(@key).to_i
end