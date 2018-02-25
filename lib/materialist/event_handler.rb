require 'active_support/inflector'
require_relative './event_worker'

module Materialist
  class EventHandler

    DEFAULT_SIDEKIQ_OPTIONS = { retry: 10 }.freeze

    def initialize
    end

    def on_events_received(batch)
      batch.each { |event| call(event) if should_materialize?(event['topic']) }
    end

    def call(event)
      worker.perform_async(event)
    end

    private

    attr_reader :topics

    def should_materialize?(topic)
      Materialist.configuration.topics.include?(topic.to_s)
    end

    def sidekiq_options
      DEFAULT_SIDEKIQ_OPTIONS.merge(Materialist.configuration.sidekiq_options)
    end

    def worker
      Materialist::EventWorker.set(sidekiq_options)
    end
  end
end
