module Materialist
  module Materializer
    module Internals
      class LinkHrefMapping
        def initialize(key:, as:, url_parser: nil)
          @key = key
          @as = as
          @url_parser = url_parser
        end

        attr_reader :key, :as

        def url_parser
          @url_parser || ->url { url }
        end
      end
    end
  end
end
