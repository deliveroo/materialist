module Materialist
  module Materializer
    module Internals
      module ClassMethods
        attr_reader :__materialist_options, :__materialist_dsl_mapping_stack

        def perform(url, action, *options)
          Materializer.new(url, self, *options).perform(action)
        end

        def _sidekiq_options
          __materialist_options[:sidekiq_options] || {}
        end
      end
    end
  end
end
