# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Sidekiq
      class << self
        def register(namespace: "Sidekiq", reporter: Speedshop::Cloudwatch.reporter)
          @namespace = namespace
          @reporter = reporter

          @reporter.register_collector do
            collect_metrics
          end
        end

        private

        def collect_metrics
          return unless defined?(::Sidekiq)

          stats = ::Sidekiq::Stats.new
          @reporter.report("enqueued", stats.enqueued, namespace: @namespace, unit: "Count")
          @reporter.report("processed", stats.processed, namespace: @namespace, unit: "Count")
          @reporter.report("failed", stats.failed, namespace: @namespace, unit: "Count")
          @reporter.report("scheduled_size", stats.scheduled_size, namespace: @namespace, unit: "Count")
          @reporter.report("retry_size", stats.retry_size, namespace: @namespace, unit: "Count")
          @reporter.report("dead_size", stats.dead_size, namespace: @namespace, unit: "Count")
          @reporter.report("workers_size", stats.workers_size, namespace: @namespace, unit: "Count")

          ::Sidekiq::Queue.all.each do |queue|
            dimensions = [{name: "QueueName", value: queue.name}]
            @reporter.report("queue_latency", queue.latency, namespace: @namespace, unit: "Seconds", dimensions: dimensions)
            @reporter.report("queue_size", queue.size, namespace: @namespace, unit: "Count", dimensions: dimensions)
          end
        end
      end
    end
  end
end
