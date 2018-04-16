module Materialist
  module Materializer
    module Internals
      class LinkMapping
        def initialize(key:, enable_caching: false)
          @key = key
          @enable_caching = enable_caching
          @mapping = []
        end

        attr_reader :key, :enable_caching, :mapping
      end
    end
  end
end
