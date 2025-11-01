# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class MetricsCollector < Speedshop::Cloudwatch::MetricsCollector
        def self.collect?(config)
          defined?(::Puma)
        end

        def collect
          stats = ::Puma.stats_hash

          if stats[:worker_status]
            %i[workers booted_workers old_workers].each do |m|
              metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
              Reporter.instance.report(metric: metric_name, value: stats[m] || 0)
            end
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
      end
    end
  end
end

Speedshop::Cloudwatch::Integration.add_integration(:puma, Speedshop::Cloudwatch::Puma::MetricsCollector)
