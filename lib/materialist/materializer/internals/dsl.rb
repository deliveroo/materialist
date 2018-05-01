module Materialist
  module Materializer
    module Internals
      module DSL
        def materialize_link(key, topic: key)
          __materialist_options[:links_to_materialize][key] = { topic: topic }
        end

        def capture(key, as: key)
          __materialist_dsl_mapping_stack.last << FieldMapping.new(key: key, as: as)
        end

        def capture_link_href(key, as:, &url_parser_block)
          __materialist_dsl_mapping_stack.last << LinkHrefMapping.new(
            key: key,
            as: as,
            url_parser: url_parser_block
          )
        end

        def link(key, enable_caching: false)
          link_mapping = LinkMapping.new(key: key, enable_caching: enable_caching)
          __materialist_dsl_mapping_stack.last << link_mapping
          __materialist_dsl_mapping_stack << link_mapping.mapping
          yield
          __materialist_dsl_mapping_stack.pop
        end

        def persist_to(klass)
          __materialist_options[:model_class] = klass
        end

        def sidekiq_options(options)
          __materialist_options[:sidekiq_options] = options
        end

        def source_key(key, &url_parser_block)
          __materialist_options[:source_key] = key
          __materialist_options[:url_parser] = url_parser_block
        end

        def before_upsert(*method_array)
          __materialist_options[:before_upsert] = method_array
        end

        def after_upsert(*method_array)
          __materialist_options[:after_upsert] = method_array
        end

        def after_destroy(*method_array)
          __materialist_options[:after_destroy] = method_array
        end

        def before_destroy(*method_array)
          __materialist_options[:before_destroy] = method_array
        end
      end
    end
  end
end
