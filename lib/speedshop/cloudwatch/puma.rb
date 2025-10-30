# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class << self
        def register(namespace: nil, reporter: Speedshop::Cloudwatch.reporter)
          @namespace = namespace || Speedshop::Cloudwatch.config.namespaces[:puma]
          @reporter = reporter

          @reporter.register_collector do
            collect_metrics
          end
        end

        private

        def collect_metrics
          return unless defined?(::Puma)

          stats = ::Puma.stats_hash
          report_stats(stats)
        end

        def report_stats(stats)
          @reporter.report("Workers", stats[:workers] || 0, namespace: @namespace, unit: "Count")
          @reporter.report("BootedWorkers", stats[:booted_workers] || 0, namespace: @namespace, unit: "Count")
          @reporter.report("OldWorkers", stats[:old_workers] || 0, namespace: @namespace, unit: "Count")

          if stats[:worker_status]
            stats[:worker_status].each_with_index do |worker, idx|
              next unless worker[:last_status]
              report_worker_stats(worker[:last_status], idx)
            end
          elsif stats[:running]
            report_worker_stats(stats, 0)
          end
        end

        def report_worker_stats(worker_stats, worker_idx)
          dimensions = [{name: "WorkerIndex", value: worker_idx.to_s}]

          @reporter.report("Running", worker_stats[:running] || 0, namespace: @namespace, unit: "Count", dimensions: dimensions)
          @reporter.report("Backlog", worker_stats[:backlog] || 0, namespace: @namespace, unit: "Count", dimensions: dimensions)
          @reporter.report("PoolCapacity", worker_stats[:pool_capacity] || 0, namespace: @namespace, unit: "Count", dimensions: dimensions)
          @reporter.report("MaxThreads", worker_stats[:max_threads] || 0, namespace: @namespace, unit: "Count", dimensions: dimensions)
        end
      end
    end
  end
end
