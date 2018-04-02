module Materialist
  module Materializer
    module Internals
      module ClassMethods
        attr_reader :__materialist_options, :__materialist_dsl_mapping_stack

        def perform(url, action)
          materializer = Materializer.new(url, self)
          action == :delete ? materializer.destroy : materializer.upsert
        end

        def prune!
          PruneRunner.new(self).run!
        end

        def prune_enabled?
          PruneRunner.new(self).enabled?
        end

        def _sidekiq_options
          __materialist_options[:sidekiq_options] || {}
        end
      end
    end
  end
end
