# frozen_string_literal: true

module RuboCop
  module Cop
    module Custom
      class ForbiddenMethods < Base
        MSG = "Avoid using `%<method>s`. Use proper encapsulation instead."

        FORBIDDEN_METHODS = %i[
          instance_variable_get
          instance_variable_set
          define_singleton_method
        ].freeze

        def on_send(node)
          return unless FORBIDDEN_METHODS.include?(node.method_name)

          add_offense(node, message: format(MSG, method: node.method_name))
        end
      end
    end
  end
end
