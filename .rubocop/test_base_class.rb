module RuboCop
  module Cop
    module Custom
      class TestBaseClass < Base
        MSG = "Test classes must inherit from SpeedshopCloudwatchTest"

        def on_class(node)
          return unless in_test_file?
          return unless test_class?(node)
          return if node.parent_class&.const_name == "SpeedshopCloudwatchTest"
          return if node.identifier.const_name == "SpeedshopCloudwatchTest"

          add_offense(node.identifier)
        end

        private

        def test_class?(node)
          node.identifier.const_name.end_with?("Test")
        end

        def in_test_file?
          processed_source.file_path.include?("/test/") &&
            processed_source.file_path.end_with?("_test.rb") &&
            !processed_source.file_path.end_with?("test_helper.rb")
        end
      end
    end
  end
end
