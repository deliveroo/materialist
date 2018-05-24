module Materialist
  module Materializer
    module Internals
      class LinkMapping
        def initialize(key:, mapping: [], enable_caching: false)
          @key = key
          @mapping = mapping
          @enable_caching = enable_caching
        end

        attr_reader :mapping

        def map(resource)
          return unless linked_resource = linked_resource(resource)
          mapping.map{ |m| m.map(linked_resource) }.compact.reduce(&:merge)
        end

        def linked_resource(resource)
          return unless href = resource.dig(:_links, @key, :href)
          resource.client.get(href, options: { enable_caching: @enable_caching })
        rescue Routemaster::Errors::ResourceNotFound
          nil
        end
      end
    end
  end
end
