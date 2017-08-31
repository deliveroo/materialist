require 'sidekiq'
require 'active_support/inflector'

module Materialist
  class EventWorker
    include Sidekiq::Worker

    def perform(event)
      topic = event['topic']
      materializer = "#{topic.to_s.singularize.classify}Materializer".constantize
      materializer.perform(event['url'], event['type'].to_sym)
    end
  end
end
