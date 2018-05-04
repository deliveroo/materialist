module Materialist
  module Materializer
    module Internals
      class LinkMapping
        def initialize(key:, enable_caching: false)
          @key = key
          @enable_caching = enable_caching
          @mapping = []
        end

        attr_reader :mapping

        def map(resource)
          return unless linked_resource = linked_resource(resource)
          mapping.map{ |m| m.map(linked_resource) }.compact.reduce(&:merge)
        end

        def linked_resource(resource)
          return unless link = resource.dig(:_links, @key)
          resource.client.get(link.href, options: { enable_caching: @enable_caching })
        rescue Routemaster::Errors::ResourceNotFound
          nil
        end
      end
    end
  end
end
