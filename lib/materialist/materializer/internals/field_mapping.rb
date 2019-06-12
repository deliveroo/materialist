module Materialist
  module Materializer
    module Internals
      class FieldMapping
        def initialize(key:, as: key, value_parser: nil)
          @key = key
          @as = as
          @value_parser = value_parser || ->value { value }
        end

        def map(resource)
          { @as => @value_parser.call(resource.dig(@key)) }
        end
      end
    end
  end
end
