# frozen_string_literal: true

module Apricity
  module Run
    # Subscriber = Data.define(:queue) do
    #   def push(event) = queue << event
    # end

    # Manage subscribers for run events
    class Subscriptions
      # In memory backend implementation
      class InMemoryBackend
        def initialize = @subscribers = Hash.new { |h, k| h[k] = [] }
        def add_subscriber(run_id, subscriber) = @subscribers[run_id] << subscriber
        def remove_subscriber(run_id, subscriber) = @subscribers[run_id].delete(subscriber)

        def dispatch(run_id, event)
          subs = @subscribers[run_id].dup
          subs.each { |subscriber| subscriber.push(event) }
        end

        def dispatch_json(run_id, event_json)
          subs = @subscribers[run_id].dup
          subs.each { |subscriber| subscriber.push(event_json) }
        end
      end

      # Redis backend implementation
      class RedisBackend
        def initialize(redis_url:)
          @redis_url = redis_url
          @in_memory = InMemoryBackend.new
          @mutex = Mutex.new
          @started = false
          @threads = {}
          @publish_queue = Queue.new
          @publisher = self.class.publisher_thread(redis_url, queue: @publish_queue)
        end

        def self.publisher_thread(redis_url, queue:)
          Thread.new { publisher_loop(redis_url, queue:) }.tap do |t|
            t.name = "apricity-redis-publisher"
            # t.abort_on_exception = true
            t.report_on_exception = true
          end
        end

        # rubocop:disable Metrics/MethodLength
        def self.publisher_loop(redis_url, queue:)
          pub = Redis.new(url: redis_url)
          loop do
            msg = queue.pop
            break if msg == :__stop__

            chan, payload = msg
            pub.publish(chan, payload)
          rescue RedisClient::ConnectionError, SystemCallError => e
            warn "publisher reconnecting after #{e.class}: #{e.message}"
            sleep 1
            pub = Redis.new(url: redis_url)
            retry
          rescue StandardError => e
            warn "publisher error: #{e.class}: #{e.message}"
          end
        end
        # rubocop:enable Metrics/MethodLength

        def ensure_started!
          return if @started

          @started = true

          Thread.new { start_pattern_subscriber_loop }.tap do |t|
            t.report_on_exception = true
          end
        end

        def start_pattern_subscriber_loop
          Thread.current.name = "apricity-redis-psub" if Thread.current.respond_to?(:name=)

          loop do
            pattern_subscribe("apricity:events_live:*") # blocks
          rescue RedisClient::ConnectionError, EOFError, SystemCallError => e
            warn "psub reconnecting after #{e.class}: #{e.message}"
            sleep 1
          rescue StandardError => e
            warn "psub unexpected error #{e.class}: #{e.message}"
            sleep 2
          end
        end

        def pattern_subscribe(pattern)
          redis = Redis.new(url: redis_url)

          redis.psubscribe(pattern) do |on|
            on.pmessage do |_pattern, channel, msg|
              run_id = channel.split(":").last

              @in_memory.dispatch(run_id, msg)
            end
          end
        ensure
          redis&.close
        end

        def add_subscriber(run_id, subscriber)
          ensure_started!
          @mutex.synchronize { @in_memory.add_subscriber(run_id, subscriber) }
        end

        def remove_subscriber(run_id, subscriber)
          @mutex.synchronize { @in_memory.remove_subscriber(run_id, subscriber) }
        end

        def dispatch(run_id, event)
          payload = Apricity::JobExecution::EventSerializer.as_json(event)
          # @publish_queue << [channel(run_id), payload]
          dispatch_json(run_id, payload)
        end

        def dispatch_json(run_id, event_json)
          @publish_queue << [channel(run_id), event_json]
        end

        private

        attr_reader :redis_url

        def channel(run_id) = "apricity:events_live:#{run_id}"
      end

      include Singleton

      def initialize(backend: RedisBackend.new(
        redis_url: ENV.fetch("REDIS_URL", "redis://localhost:6379")
      ))
        @backend = backend
      end

      def add_subscriber(run_id, subscriber) = backend.add_subscriber(run_id, subscriber)
      def remove_subscriber(run_id, subscriber) = backend.remove_subscriber(run_id, subscriber)
      def dispatch(run_id, event) = backend.dispatch(run_id, event)
      def dispatch_json(run_id, event_json) = backend.dispatch_json(run_id, event_json)

      def self.add_subscriber(run_id, subscriber) = instance.add_subscriber(run_id, subscriber)
      def self.remove_subscriber(run_id, subscriber) = instance.remove_subscriber(run_id, subscriber)
      def self.dispatch(run_id, event) = instance.dispatch(run_id, event)
      def self.dispatch_json(run_id, event_json) = instance.dispatch_json(run_id, event_json)

      private

      attr_reader :backend
    end
  end
end
