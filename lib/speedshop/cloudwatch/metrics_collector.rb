module Speedshop
  module Cloudwatch
    class MetricsCollector
      def self.collect?(config)
        true
      end

      def initialize(config: Config.instance)
        @config = config
      end

      def collect
        []
      end

      private

      attr_reader :config
    end
  end
end
