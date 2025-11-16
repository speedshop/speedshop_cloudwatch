# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricAggregator
      def aggregate(metrics)
        grouped = group_by_key(metrics)
        grouped.values.map { |items| aggregate_items(items) }
      end

      private

      def group_by_key(metrics)
        metrics.each_with_object({}) do |metric, groups|
          key = metric_key(metric)
          (groups[key] ||= []) << metric
        end
      end

      def metric_key(metric)
        [
          metric[:metric_name],
          metric[:unit],
          normalized_dimensions(metric[:dimensions])
        ]
      end

      def normalized_dimensions(dims)
        return "" unless dims

        dims.sort_by { |d| d[:name].to_s }
          .map { |d| "#{d[:name]}=#{d[:value]}" }
          .join("|")
      end

      def aggregate_items(items)
        return items.first if single_item?(items)

        build_aggregated_metric(items)
      end

      def single_item?(items)
        items.size == 1
      end

      def build_aggregated_metric(items)
        stats = calculate_statistics(items)
        {
          metric_name: items.first[:metric_name],
          unit: items.first[:unit],
          dimensions: items.first[:dimensions],
          timestamp: Time.now,
          statistic_values: stats
        }
      end

      def calculate_statistics(items)
        sample_count, sum, min, max = reduce_items(items)
        {
          sample_count: sample_count,
          sum: sum,
          minimum: finite_or_zero(min),
          maximum: finite_or_zero(max)
        }
      end

      def reduce_items(items)
        initial = [0.0, 0.0, Float::INFINITY, -Float::INFINITY]
        items.reduce(initial) do |acc, item|
          merge_item(acc, item)
        end
      end

      def merge_item(acc, item)
        item[:statistic_values] ?
          merge_statistic_values(acc, item[:statistic_values]) :
          merge_single_value(acc, item[:value])
      end

      def merge_statistic_values(acc, stats)
        count, sum, min, max = acc
        sc = stats[:sample_count].to_f
        [
          count + sc,
          sum + stats[:sum].to_f,
          [min, stats[:minimum].to_f].min,
          [max, stats[:maximum].to_f].max
        ]
      end

      def merge_single_value(acc, value)
        return acc unless value

        count, sum, min, max = acc
        v = value.to_f
        [count + 1.0, sum + v, [min, v].min, [max, v].max]
      end

      def finite_or_zero(value)
        value.finite? ? value : 0.0
      end
    end
  end
end
