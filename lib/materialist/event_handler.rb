require 'active_support/inflector'
require_relative './event_worker'
require_relative './materializer_factory'

module Materialist
  class EventHandler

    DEFAULT_SIDEKIQ_OPTIONS = { retry: 10 }.freeze

    def on_events_received(batch)
      batch.each { |event| call(event) if should_materialize?(topic(event)) }
    end

    def call(event)
      worker(topic(event)).perform_async(event)
    end

    private

    def topic(event)
      event['topic'].to_s
    end

    def should_materialize?(topic)
      Materialist.configuration.topics.include?(topic)
    end

    def sidekiq_options(topic)
      [
        DEFAULT_SIDEKIQ_OPTIONS,
        Materialist.configuration.sidekiq_options,
        materializer_sidekiq_options(topic)
      ].inject(:merge)
    end

    def worker(topic)
      Materialist::EventWorker.set(sidekiq_options(topic))
    end

    def materializer_sidekiq_options(topic)
      Materialist::MaterializerFactory.class_from_topic(topic)._sidekiq_options
    end
  end
end
