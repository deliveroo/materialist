require 'routemaster/api_client'

module Routemaster
  module Indexer
    VERSION = '0.0.1'

    def self.included(base)
      base.extend(Internals::ClassMethods)
      base.extend(Internals::DSL)

      root_mapping = []
      base.instance_variable_set(:@rm_indexer_options, { mapping: root_mapping })
      base.instance_variable_set(:@__rm_indexer_dsl_mapping_stack, [root_mapping])
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

      module ClassMethods
        attr_reader :rm_indexer_options, :__rm_indexer_dsl_mapping_stack

        def perform(url, action)
          indexer = Indexer.new(url, self)
          action == :delete ? indexer.destroy : indexer.upsert
        end
      end

      module DSL

        def index(key, as: key)
          __rm_indexer_dsl_mapping_stack.last << FieldMapping.new(key: key, as: as)
        end

        def link(key)
          link_mapping = LinkMapping.new(key: key)
          __rm_indexer_dsl_mapping_stack.last << link_mapping
          __rm_indexer_dsl_mapping_stack << link_mapping.mapping
          yield
          __rm_indexer_dsl_mapping_stack.pop
        end

        def use_model(klass)
          rm_indexer_options[:model_class] = klass
        end

        def after_index(method_name)
          rm_indexer_options[:after_index] = method_name
        end

      end

      class Indexer

        def initialize(url, klass)
          @url = url
          @instance = klass.new
          @options = klass.rm_indexer_options
        end

        def upsert
          upsert_record.tap do |entity|
            instance.send(after_index, entity) if after_index
          end
        end

        def destroy
          model_class.where(source_url: url).destroy_all
        end

        private

        attr_reader :url, :instance, :options

        def upsert_record
          model_class.find_or_initialize_by(source_url: url).tap do |entity|
            entity.update_attributes attributes
            entity.save!
          end
        end

        def mapping
          options.fetch :mapping
        end

        def after_index
          options[:after_index]
        end

        def model_class
          options.fetch(:model_class).to_s.classify.constantize
        end

        def attributes
          build_attributes resource_at(url), mapping
        end

        def build_attributes(resource, mapping)
          return {} unless resource

          mapping.inject({}) do |result, m|
            case m
            when FieldMapping
              result.tap { |r| r[m.as] = resource.body[m.key] }
            when LinkMapping
              resource.body._links.include?(m.key) ?
                result.merge(build_attributes(resource_at(resource.send(m.key).url, allow_nil: true), m.mapping || [])) :
                result
            else
              result
            end
          end
        end

        def resource_at(url, allow_nil: false)
          api_client.get(url, options: { enable_caching: false })
        rescue Routemaster::Errors::ResourceNotFound
          raise unless allow_nil
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
