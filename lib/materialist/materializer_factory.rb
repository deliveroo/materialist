module Materialist
  class MaterializerFactory
    def self.class_from_topic(topic)
      "#{topic.to_s.singularize.classify}Materializer".safe_constantize
    end
  end
end
