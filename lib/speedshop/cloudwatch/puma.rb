# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class << self
        def start!(namespace: "Puma", interval: 60, client: nil)
          @reporter = MetricReporter.new(
            namespace: namespace,
            interval: interval,
            client: client
          )
          @reporter.start!
          @collection_thread = Thread.new { collect_loop(interval) }
        end

        def stop!
          @collection_thread&.kill
          @reporter&.stop!
        end

        private

        def collect_loop(interval)
          loop do
            collect_metrics
            sleep interval
          end
        rescue => e
          warn "Puma metrics collection error: #{e.message}"
        end

        def collect_metrics
          return unless defined?(::Puma)

          stats = ::Puma.stats_hash
          report_stats(stats)
        end

        def report_stats(stats)
          @reporter.report("workers", stats[:workers] || 0, unit: "Count")
          @reporter.report("booted_workers", stats[:booted_workers] || 0, unit: "Count")
          @reporter.report("old_workers", stats[:old_workers] || 0, unit: "Count")

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

          @reporter.report("running", worker_stats[:running] || 0, unit: "Count", dimensions: dimensions)
          @reporter.report("backlog", worker_stats[:backlog] || 0, unit: "Count", dimensions: dimensions)
          @reporter.report("pool_capacity", worker_stats[:pool_capacity] || 0, unit: "Count", dimensions: dimensions)
          @reporter.report("max_threads", worker_stats[:max_threads] || 0, unit: "Count", dimensions: dimensions)
        end
      end
    end
  end
end
