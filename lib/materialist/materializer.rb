require 'active_support/inflector'
require 'routemaster/api_client'
require_relative './event_worker'

module Materialist
  module Materializer

    def self.included(base)
      base.extend(Internals::ClassMethods)
      base.extend(Internals::DSL)

      root_mapping = []
      base.instance_variable_set(:@__materialist_options, {
        mapping: root_mapping,
        links_to_materialize: {}
      })
      base.instance_variable_set(:@__materialist_dsl_mapping_stack, [root_mapping])
    end

    module Internals
      class FieldMapping
        def initialize(key:, as:)
          @key = key
          @as = as
        end

        attr_reader :key, :as
      end

      class LinkMapping
        def initialize(key:)
          @key = key
          @mapping = []
        end

        attr_reader :key, :mapping
      end

      class LinkHrefMapping
        def initialize(key:, as:)
          @key = key
          @as = as
        end

        attr_reader :key, :as
      end

      module ClassMethods
        attr_reader :__materialist_options, :__materialist_dsl_mapping_stack

        def perform(url, action)
          materializer = Materializer.new(url, self)
          action == :delete ? materializer.destroy : materializer.upsert
        end
      end

      module DSL

        def materialize_link(key, topic: key)
          __materialist_options[:links_to_materialize][key] = { topic: topic }
        end

        def capture(key, as: key)
          __materialist_dsl_mapping_stack.last << FieldMapping.new(key: key, as: as)
        end

        def capture_link_href(key, as:)
          __materialist_dsl_mapping_stack.last << LinkHrefMapping.new(key: key, as: as)
        end

        def link(key)
          link_mapping = LinkMapping.new(key: key)
          __materialist_dsl_mapping_stack.last << link_mapping
          __materialist_dsl_mapping_stack << link_mapping.mapping
          yield
          __materialist_dsl_mapping_stack.pop
        end

        def persist_to(klass)
          __materialist_options[:model_class] = klass
        end

        def after_upsert(method_name)
          __materialist_options[:after_upsert] = method_name
        end

        def after_destroy(method_name)
          __materialist_options[:after_destroy] = method_name
        end
      end

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
              instance.send(after_upsert, entity) if after_upsert
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
          model_class.find_by(source_url: url).tap do |entity|
            entity.destroy!.tap do |entity|
              instance.send(after_destroy, entity) if after_destroy
            end if entity
          end
        end

        private

        attr_reader :url, :instance, :options

        def materialize_self?
          options.include? :model_class
        end

        def upsert_record
          model_class.find_or_initialize_by(source_url: url).tap do |entity|
            entity.update_attributes attributes
            entity.save!
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
          ::Materialist::EventWorker.new.perform({
            'topic' => opts[:topic],
            'url' => root_resource.body._links[key].href,
            'type' => 'noop'
          })
        end

        def mapping
          options.fetch :mapping
        end

        def after_upsert
          options[:after_upsert]
        end

        def after_destroy
          options[:after_destroy]
        end

        def model_class
          options.fetch(:model_class).to_s.camelize.constantize
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
      end
    end
  end
end
