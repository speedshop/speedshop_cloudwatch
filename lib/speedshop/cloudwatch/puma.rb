# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Puma
      def collect
        stats = ::Puma.stats_hash

        if stats[:worker_status]
          %i[workers booted_workers old_workers].each do |m|
            Reporter.instance.report(metric: metric_name_for(m), value: stats[m] || 0)
          end
          report_aggregate_worker_stats(stats)
        else
          # Single mode - report worker stats without dimensions
          %i[running backlog pool_capacity max_threads].each do |m|
            Reporter.instance.report(metric: metric_name_for(m), value: stats[m] || 0)
          end
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Puma metrics: #{e.message}", e)
      end

      private

      def report_aggregate_worker_stats(stats)
        statuses = stats[:worker_status].map { |w| w[:last_status] || {} }
        metrics = %i[running backlog pool_capacity max_threads]

        metrics.each do |m|
          values = statuses.map { |s| s[m] }.compact
          next if values.empty?

          sample_count = values.length
          sum = values.inject(0) { |acc, v| acc + v.to_f }
          minimum = values.min.to_f
          maximum = values.max.to_f

          Reporter.instance.report(
            metric: metric_name_for(m),
            statistic_values: {
              sample_count: sample_count,
              sum: sum,
              minimum: minimum,
              maximum: maximum
            },
            integration: :puma
          )
        end
      end

      def metric_name_for(symbol)
        symbol.to_s.split("_").map(&:capitalize).join.to_sym
      end
    end
  end
end
