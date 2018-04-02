require 'routemaster/api_client'
require_relative '../../errors'

module Materialist
  module Materializer
    module Internals
      class PruneRunner
        def initialize(klass)
          @klass = klass
          @options = klass.__materialist_options
        end

        def enabled?
          !!prune_after
        end

        def run!
          raise PruningNotEnabled unless prune_after

          model_class.where('updated_at < ?', prune_after.ago).destroy_all
        end

        private

        attr_reader :klass, :options

        def model_class
          options.fetch(:model_class).to_s.camelize.constantize
        end

        def prune_after
          options.fetch(:prune, {}).fetch(:after, nil)
        end
      end
    end
  end
end
