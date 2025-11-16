# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Puma
      def collect
        stats = ::Puma.stats_hash
        report_cluster_metrics(stats) if clustered?(stats)
        report_all_workers(stats)
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Puma metrics: #{e.message}", e)
      end

      private

      def clustered?(stats)
        stats[:worker_status]
      end

      def report_cluster_metrics(stats)
        report_cluster_counts(stats)
        report_aggregate_worker_stats(stats)
      end

      def report_cluster_counts(stats)
        %i[workers booted_workers old_workers].each do |metric|
          report_metric(metric, stats[metric] || 0)
        end
      end

      def report_all_workers(stats)
        workers_list(stats).each { |worker_stats, idx| report_worker(worker_stats, idx) }
      end

      def workers_list(stats)
        clustered?(stats) ? worker_statuses(stats) : [[stats, 0]]
      end

      def worker_statuses(stats)
        stats[:worker_status].map.with_index { |w, idx| [w[:last_status] || {}, idx] }
      end

      def report_worker(stats, idx)
        worker_metrics.each do |metric|
          report_metric(metric, stats[metric] || 0, WorkerIndex: idx.to_s)
        end
      end

      def worker_metrics
        %i[running backlog pool_capacity max_threads]
      end

      def report_aggregate_worker_stats(stats)
        statuses = extract_statuses(stats)
        worker_metrics.each { |metric| report_aggregated_metric(metric, statuses) }
      end

      def extract_statuses(stats)
        stats[:worker_status].map { |w| w[:last_status] || {} }
      end

      def report_aggregated_metric(metric, statuses)
        values = collect_values(metric, statuses)
        return if values.empty?

        report_statistic_values(metric, values)
      end

      def collect_values(metric, statuses)
        statuses.map { |s| s[metric] }.compact
      end

      def report_statistic_values(metric, values)
        Reporter.instance.report(
          metric: metric_name(metric),
          statistic_values: build_statistics(values),
          integration: :puma
        )
      end

      def build_statistics(values)
        {
          sample_count: values.length,
          sum: values.sum(&:to_f),
          minimum: values.min.to_f,
          maximum: values.max.to_f
        }
      end

      def report_metric(metric, value, dimensions = {})
        Reporter.instance.report(
          metric: metric_name(metric),
          value: value,
          dimensions: dimensions
        )
      end

      def metric_name(symbol)
        symbol.to_s.split("_").map(&:capitalize).join.to_sym
      end
    end
  end
end
