require_relative '../../workers/event'
require_relative './resources'

module Materialist
  module Materializer
    module Internals
      class Materializer
        def initialize(url, klass, resource_payload: nil, api_client: nil)
          @url = url
          @instance = klass.new
          @options = klass.__materialist_options
          @api_client = api_client || Materialist.configuration.api_client
          if resource_payload
            @resource = PayloadResource.new(resource_payload, client: @api_client)
          end
        end

        def perform(action)
          action.to_sym == :delete ? destroy : upsert
        end

        private

        def upsert(retry_on_race_condition: true)
          return unless resource

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

        attr_reader :url, :instance, :options, :api_client

        def materialize_self?
          options.include? :model_class
        end

        def upsert_record
          model_class.find_or_initialize_by(source_lookup(url)).tap do |entity|
            send_messages(before_upsert, entity) unless before_upsert.nil?
            entity.update_attributes!(attributes)
          end
        end

        def materialize_links
          (options[:links_to_materialize] || [])
            .each { |key, opts| materialize_link(key, opts) }
        end

        def materialize_link(key, opts)
          return unless link = resource.dig(:_links, key)
          return unless materializer_class = MaterializerFactory.class_from_topic(opts.fetch(:topic))

          # TODO: perhaps consider doing this asynchronously some how?
          materializer_class.perform(link[:href], :noop)
        end

        def mappings
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
          mappings.map{ |m| m.map(resource) }.compact.reduce(&:merge) || {}
        end

        def resource
          @resource ||= fetch_resource
        end

        def fetch_resource
          api_client.get(url, options: { enable_caching: false, response_class: HateoasResource })
        rescue Routemaster::Errors::ResourceNotFound
          nil
        end

        def send_messages(messages, arguments)
          messages.each { |message| instance.send(message, arguments) }
        end
      end
    end
  end
end
