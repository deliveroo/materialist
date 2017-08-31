require 'active_support/inflector'
require_relative './event_worker'

module Materialist
  class EventHandler

    def initialize(options={})
      @options = options
    end

    def on_events_received(batch)
      batch.each { |event| call(event) if topics.include?(event['topic'].to_s) }
    end

    def call(event)
      worker.perform_async(event)
    end

    private

    attr_reader :options

    def topics
      @_topics ||= options.fetch(:topics, []).map(&:to_s)
    end

    def worker
      @_worker ||= Materialist::EventWorker.set(options.slice(:queue))
    end
  end
end
