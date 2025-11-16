# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricBuilder
      def initialize(config:)
        @config = config
      end

      def build_datum(metric:, value: nil, statistic_values: nil, dimensions: {}, namespace: nil, integration: nil)
        int = integration || find_integration(metric)
        return nil unless int && metric_allowed?(int, metric)

        {
          metric_name: metric.to_s,
          namespace: namespace || @config.namespaces[int],
          unit: @config.units[metric] || "None",
          dimensions: build_dimensions(dimensions),
          timestamp: Time.now
        }.tap do |datum|
          add_value(datum, value, statistic_values)
        end
      end

      def build_for_cloudwatch(metrics, high_resolution:)
        metrics.map do |m|
          build_cloudwatch_datum(m, high_resolution)
        end
      end

      private

      def build_dimensions(dimensions)
        metric_dims = dimensions.map { |k, v| dimension_hash(k, v) }
        metric_dims + custom_dimensions
      end

      def dimension_hash(key, value)
        {name: key.to_s, value: value.to_s}
      end

      def custom_dimensions
        @config.dimensions.map { |k, v| dimension_hash(k, v) }
      end

      def add_value(datum, value, statistic_values)
        if statistic_values
          datum[:statistic_values] = statistic_values
        else
          datum[:value] = value
        end
      end

      def build_cloudwatch_datum(metric, high_resolution)
        {
          metric_name: metric[:metric_name],
          unit: metric[:unit],
          timestamp: metric[:timestamp],
          dimensions: metric[:dimensions]
        }.tap do |datum|
          add_metric_data(datum, metric)
          datum[:storage_resolution] = 1 if high_resolution
        end
      end

      def add_metric_data(datum, metric)
        metric[:statistic_values] ?
          datum[:statistic_values] = metric[:statistic_values] :
          datum[:value] = metric[:value]
      end

      def find_integration(metric)
        @config.metrics.find do |int, metrics|
          metrics.include?(metric.to_sym)
        end&.first
      end

      def metric_allowed?(integration, metric)
        @config.metrics[integration].include?(metric.to_sym)
      end
    end
  end
end
