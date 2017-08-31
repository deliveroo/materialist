require 'sidekiq'
require 'active_support/inflector'

module Routemaster
  module Indexer
    class EventWorker
      include Sidekiq::Worker

      def perform(event)
        topic = event['topic']
        indexer = "#{topic.to_s.singularize.classify}Indexer".constantize
        indexer.perform event["url"]
      end
    end
  end
end
