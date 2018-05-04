module Materialist
  module Materializer
    module Internals
      class LinkHrefMapping
        def initialize(key:, as:, url_parser: nil)
          @key = key
          @as = as
          @url_parser = url_parser
        end

        def map(resource)
          return unless link = resource.dig(:_links, @key)
          { @as => url_parser.call(link.href) }
        end

        private

        def url_parser
          @url_parser || ->url { url }
        end
      end
    end
  end
end
