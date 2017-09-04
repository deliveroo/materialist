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
            (via ? [via, key] : [key])
              .inject(source_raw) do |res, path|
                begin
                  (res && res.body._links.include?(path)) ?
                    res.send(path).show :
                    nil
                rescue Routemaster::Errors::ResourceNotFound
                  nil
                end
              end
              &.body
          end
        end
      end
    end

    def source
      source_raw&.body
    end

    private

    def source_raw
      _rm_api_client.get(source_url)
    rescue Routemaster::Errors::ResourceNotFound
      nil
    end

    def _rm_api_client
      Routemaster::APIClient.new(
        response_class: Routemaster::Responses::HateoasResponse
      )
    end
  end
end
