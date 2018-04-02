module Materialist
  module Materializer
    module Internals
      class LinkMapping
        def initialize(key:)
          @key = key
          @mapping = []
        end

        attr_reader :key, :mapping
      end
    end
  end
end
