module Speedshop
  module Cloudwatch
    module Integration
      class Registration
        attr_reader :name, :collector_class, :config

        def initialize(name, collector_class, config: nil)
          @name = name
          @collector_class = collector_class
          @config = config
        end
      end

      class << self
        def integrations
          @integrations ||= []
        end

        def add_integration(name, collector_class, config: nil)
          return if integrations.any? { |i| i.name == name }
          integrations << Registration.new(name, collector_class, config: config)
          Config.instance.expose_integration_config(name, config) if config
        end

        def clear_integrations
          @integrations = []
        end
      end
    end
  end
end
