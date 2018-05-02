require 'sidekiq'
require_relative '../materializer_factory'

module Materialist
  module Workers
      class Event
      include Sidekiq::Worker

      def perform(event)
        topic = event['topic']
        action = event['type'].to_sym
        timestamp = event['t']

        materializer = Materialist::MaterializerFactory.class_from_topic(topic)
        materializer.perform(event['url'], action)

        report_latency(topic, timestamp) if timestamp
        report_stats(topic, action, :success)
      rescue Exception => exception
        report_stats(topic, action, :failure)
        notice_error(exception, event)
        raise
      end

      private

      def report_latency(topic, timestamp)
        t = (Time.now.to_f - (timestamp.to_i / 1e3)).round(1)
        Materialist.configuration.metrics_client.histogram(
          "materialist.event_latency",
          t,
          tags: ["topic:#{topic}"]
        )
      end

      def report_stats(topic, action, kind)
        Materialist.configuration.metrics_client.increment(
          "materialist.event_worker.#{kind}",
          tags: ["action:#{action}", "topic:#{topic}"]
        )
      end

      def notice_error(exception, event)
        return unless handler = Materialist.configuration.notice_error
        handler.call(exception, event)
      end
    end
  end
end
