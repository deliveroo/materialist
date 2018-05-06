module Materialist
  module Materializer
    module Internals
      class FieldMapping
        def initialize(key:, as:)
          @key = key
          @as = as
        end

        def map(resource)
          { @as => resource.dig(@key) }
        end
      end
    end
  end
end
