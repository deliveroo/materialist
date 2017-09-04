require 'routemaster/api_client'

module Materialist
  module MaterializedRecord

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def source_link_reader(*keys, via: nil)
        keys.each do |key|
          define_method(key) do
            begin
              raw = source_raw
              raw = raw.send(via).show if via
              raw ? raw.send(key).show.body : nil
            rescue Routemaster::Errors::ResourceNotFound
              nil
            end
          end
        end
      end
    end

    def source
      source_raw&.body
    end

    def source_raw
      api_client.get(source_url)
    rescue Routemaster::Errors::ResourceNotFound
      nil
    end

    def api_client
      @_api_client ||= Routemaster::APIClient.new(
        response_class: Routemaster::Responses::HateoasResponse
      )
    end
  end
end
