# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class Collector
        def collect
          stats = ::Puma.stats_hash

          if stats[:worker_status]
            %i[workers booted_workers old_workers].each do |m|
              metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
              Reporter.instance.report(metric: metric_name, value: stats[m] || 0)
            end
            report_aggregate_worker_stats(stats)
          end

          workers = stats[:worker_status] ? worker_statuses(stats) : [[stats, 0]]
          workers.each { |worker_stats, idx| report_worker(worker_stats, idx) }
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Puma metrics: #{e.message}", e)
        end

        private

        def worker_statuses(stats)
          stats[:worker_status].map.with_index { |w, idx| [w[:last_status] || {}, idx] }
        end

        def report_worker(stats, idx)
          %i[running backlog pool_capacity max_threads].each do |m|
            metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
            Reporter.instance.report(metric: metric_name, value: stats[m] || 0, dimensions: {WorkerIndex: idx.to_s})
          end
        end

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

            metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
            Reporter.instance.report(
              metric: metric_name,
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
      end
    end
  end
end
