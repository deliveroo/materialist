module Materialist
  module Materializer
    module Internals
      module DSL
        def materialize_link(key, topic: key)
          __materialist_options[:links_to_materialize][key] = { topic: topic }
        end

        def capture(key, as: key, &value_parser_block)
          __materialist_dsl_mapping_stack.last << FieldMapping.new(
            key: key,
            as: as,
            value_parser: value_parser_block
          )
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

        # This method is meant to be used for cases when the application needs
        # to have access to the `payload` that is returned on the HTTP call.
        # Such an example would be if the application logic requires all
        # relationships to be present before the `resource` is saved in the
        # database. Introduced in https://github.com/deliveroo/materialist/pull/47
        def before_upsert_with_payload(*method_array)
          __materialist_options[:before_upsert_with_payload] = method_array
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
