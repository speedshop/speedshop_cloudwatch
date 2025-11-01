# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class << self
        def register(namespace: nil, reporter: Speedshop::Cloudwatch.reporter)
          @namespace = namespace || Speedshop::Cloudwatch.config.namespaces[:puma]
          @reporter = reporter
          @reporter.register_collector(:puma) { collect_metrics }
        end

        private

        def collect_metrics
          return unless defined?(::Puma)
          stats = ::Puma.stats_hash

          if stats[:worker_status]
            %i[workers booted_workers old_workers].each do |m|
              # Submit to SnakeCase tyranny
              metric_name = m.to_s.split("_").map(&:capitalize).join
              @reporter.report(metric_name, stats[m] || 0, namespace: @namespace, unit: "Count")
            end
          end

          workers = stats[:worker_status] ? worker_statuses(stats) : [[stats, 0]]
          workers.each { |worker_stats, idx| report_worker(worker_stats, idx) }
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Puma metrics: #{e.message}", e)
        end

        def worker_statuses(stats)
          stats[:worker_status].map { |w| [w[:last_status], stats[:worker_status].index(w)] if w[:last_status] }.compact
        end

        def report_worker(stats, idx)
          dims = [{name: "WorkerIndex", value: idx.to_s}]
          %i[running backlog pool_capacity max_threads].each do |m|
            metric_name = m.to_s.split("_").map(&:capitalize).join
            @reporter.report(metric_name, stats[m] || 0, namespace: @namespace, unit: "Count", dimensions: dims)
          end
        end
      end
    end
  end
end
