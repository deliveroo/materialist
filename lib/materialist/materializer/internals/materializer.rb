require 'routemaster/api_client'
require_relative '../../workers/event'

module Materialist
  module Materializer
    module Internals
      class Materializer
        def initialize(url, klass)
          @url = url
          @instance = klass.new
          @options = klass.__materialist_options
        end

        def upsert(retry_on_race_condition: true)
          return unless root_resource

          if materialize_self?
            upsert_record.tap do |entity|
              send_messages(after_upsert, entity) unless after_upsert.nil?
            end
          end

          materialize_links
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          # when there is a race condition and uniqueness of :source_url
          # is enforced by database index, this error is raised
          # so we simply try upsert again
          # if error is due to another type of uniqueness constraint
          # second call will also fail and error would bubble up
          retry_on_race_condition ?
            upsert(retry_on_race_condition: false) :
            raise
        end

        def destroy
          return unless materialize_self?
          model_class.find_by(source_lookup(url)).tap do |entity|
            send_messages(before_destroy, entity) unless before_destroy.nil?
            entity.destroy!.tap do |entity|
              send_messages(after_destroy, entity) unless after_destroy.nil?
            end if entity
          end
        end

        private

        attr_reader :url, :instance, :options

        def materialize_self?
          options.include? :model_class
        end

        def upsert_record
          model_class.find_or_initialize_by(source_lookup(url)).tap do |entity|
            send_messages(before_upsert, entity) unless before_upsert.nil?
            entity.update_attributes! attributes
          end
        end

        def materialize_links
          (options[:links_to_materialize] || [])
            .each { |key, opts| materialize_link(key, opts) }
        end

        def materialize_link(key, opts)
          return unless root_resource.body._links.include?(key)

          # this can't happen asynchronously
          # because the handler options are unavailable in this context
          # :(
          ::Materialist::Workers::Event.new.perform({
            'topic' => opts[:topic],
            'url' => root_resource.body._links[key].href,
            'type' => 'noop'
          })
        end

        def mapping
          options.fetch :mapping
        end

        def before_upsert
          options[:before_upsert]
        end

        def after_upsert
          options[:after_upsert]
        end

        def before_destroy
          options[:before_destroy]
        end

        def after_destroy
          options[:after_destroy]
        end

        def model_class
          options.fetch(:model_class).to_s.camelize.constantize
        end

        def source_key
          options.fetch(:source_key, :source_url)
        end

        def url_parser
          options[:url_parser] || ->url { url }
        end

        def source_lookup(url)
          @_source_lookup ||= { source_key => url_parser.call(url) }
        end

        def attributes
          build_attributes root_resource, mapping
        end

        def root_resource
          @_root_resource ||= resource_at(url)
        end

        def build_attributes(resource, mapping)
          return {} unless resource

          mapping.inject({}) do |result, m|
            case m
              when FieldMapping
                result.tap { |r| r[m.as] = resource.body[m.key] }
              when LinkHrefMapping
                result.tap do |r|
                  if resource.body._links.include?(m.key)
                    r[m.as] = resource.body._links[m.key].href
                  end
                end
              when LinkMapping
                resource.body._links.include?(m.key) ?
                  result.merge(build_attributes(resource_at(resource.send(m.key).url), m.mapping || [])) :
                  result
              else
                result
            end
          end
        end

        def resource_at(url)
          api_client.get(url, options: { enable_caching: false })
        rescue Routemaster::Errors::ResourceNotFound
          # this is due to a race condition between an upsert event
          # and a :delete event
          # when this happens we should silently ignore the case
          nil
        end

        def api_client
          @_api_client ||= Routemaster::APIClient.new(
            response_class: Routemaster::Responses::HateoasResponse
          )
        end

        def send_messages(messages, arguments)
          messages.each { |message| instance.send(message, arguments) }
        end
      end
    end
  end
end
