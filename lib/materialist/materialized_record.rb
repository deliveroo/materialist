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
            raw = source_raw
            raw = _rm_try_read_link(raw, via) if via
            raw ? _rm_try_read_link(raw, key)&.body : nil
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

    private

    def _rm_try_read_link(source, key)
      source.body._links.include?(key) ?
        source.send(key).show :
        nil
    rescue Routemaster::Errors::ResourceNotFound
      nil
    end
  end
end
