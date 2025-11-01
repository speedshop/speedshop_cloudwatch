# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class << self
        def register(reporter: Speedshop::Cloudwatch.reporter)
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
              metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
              @reporter.report(metric: metric_name, value: stats[m] || 0)
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
          %i[running backlog pool_capacity max_threads].each do |m|
            metric_name = m.to_s.split("_").map(&:capitalize).join.to_sym
            @reporter.report(metric: metric_name, value: stats[m] || 0, dimensions: {WorkerIndex: idx.to_s})
          end
        end
      end
    end
  end
end
