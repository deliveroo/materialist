require 'sidekiq'
require 'active_support/inflector'

module Materialist
  class EventWorker
    include Sidekiq::Worker

    def perform(event)
      topic = event['topic']
      action = event['type'].to_sym
      materializer = "#{topic.to_s.singularize.classify}Materializer".constantize

      materializer.perform(event['url'], action)
      report_stats(topic, action, :success)
    rescue
      report_stats(topic, action, :failure)
      raise
    end

    private

    def report_stats(topic, action, kind)
      Materialist.configuration.metrics_client.increment(
        "materialist.event_worker.#{kind}",
        tags: ["action:#{action}", "topic:#{topic}"]
      )
    end
  end
end
