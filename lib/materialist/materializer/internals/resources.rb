module Materialist
  module Materializer
    module Internals
      class PayloadResource
        attr_reader :client

        delegate :[], :dig, to: :@payload

        def initialize(payload, client:)
          @payload = payload
          @client = client
        end
      end

      class HateoasResource < PayloadResource
        def initialize(response, client:)
          super(response.body, client: client)
        end
      end
    end
  end
end
