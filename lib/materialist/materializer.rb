require_relative './materializer/internals'

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
  end
end
