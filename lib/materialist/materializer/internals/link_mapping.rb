module Materialist
  module Materializer
    module Internals
      class LinkMapping
        def initialize(key:, enable_caching: false)
          @key = key
          @enable_caching = enable_caching
          @mapping = []
        end

        def map(resource)
          return unless linked_resource = linked_resource(resource)
          mapping.map{ |m| m.map(linked_resource) }.compact.reduce(&:merge)
        end

        attr_reader :mapping

        private

        def linked_resource(resource)
          return unless resource.body._links.include?(@key)
          return unless sub_resource = resource.send(@key)
          sub_resource.show(enable_caching: @enable_caching)
        rescue Routemaster::Errors::ResourceNotFound
          nil
        end
      end
    end
  end
end
