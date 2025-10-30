# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Puma
      class << self
        def register(namespace: nil, reporter: Speedshop::Cloudwatch.reporter)
          @namespace = namespace || Speedshop::Cloudwatch.config.namespaces[:puma]
          @reporter = reporter
          @reporter.register_collector { collect_metrics }
        end

        private

        def collect_metrics
          return unless defined?(::Puma)
          stats = ::Puma.stats_hash
          %i[workers booted_workers old_workers].each { |m| @reporter.report(m.to_s.split("_").map(&:capitalize).join, stats[m] || 0, namespace: @namespace, unit: "Count") }

          workers = stats[:worker_status] ? stats[:worker_status].map { |w| [w[:last_status], stats[:worker_status].index(w)] if w[:last_status] }.compact : [[stats, 0]]
          workers.each { |worker_stats, idx| report_worker(worker_stats, idx) }
        end

        def report_worker(stats, idx)
          dims = [{name: "WorkerIndex", value: idx.to_s}]
          %i[running backlog pool_capacity max_threads].each do |m|
            @reporter.report(m.to_s.split("_").map(&:capitalize).join, stats[m] || 0, namespace: @namespace, unit: "Count", dimensions: dims)
          end
        end
      end
    end
  end
end
