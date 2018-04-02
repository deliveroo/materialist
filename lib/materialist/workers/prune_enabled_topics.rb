require 'sidekiq'
require_relative '../materializer_factory'
require_relative 'prune_topic'

module Materialist
  module Workers
    class PruneEnabledTopics
      include Sidekiq::Worker

      def perform
        topics.each do |topic|
          PruneTopic.perform_async(topic) if prune_enabled?(topic)
        end
      end

      private

      def topics
        Materialist.configuration.topics
      end

      def prune_enabled?(topic)
        materializer_class = Materialist::MaterializerFactory.class_from_topic(topic)
        materializer_class.prune_enabled?
      end
    end
  end
end
