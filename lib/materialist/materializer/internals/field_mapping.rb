module Materialist
  module Materializer
    module Internals
      class FieldMapping
        def initialize(key:, as:)
          @key = key
          @as = as
        end

        attr_reader :key, :as
      end
    end
  end
end
