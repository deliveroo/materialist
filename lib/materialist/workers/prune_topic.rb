require 'sidekiq'
require_relative '../materializer_factory'

module Materialist
  module Workers
    class PruneTopic
      include Sidekiq::Worker

      def perform(topic)
        materializer_class = Materialist::MaterializerFactory.class_from_topic(topic)
        materializer_class.prune!
      end
    end
  end
end
