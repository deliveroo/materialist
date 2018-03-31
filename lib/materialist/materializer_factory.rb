module Materialist
  class MaterializerFactory
    def self.class_from_topic(topic)
      "#{topic.to_s.singularize.classify}Materializer".constantize
    rescue NameError
      nil
    end
  end
end
