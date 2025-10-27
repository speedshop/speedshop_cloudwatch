# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Sidekiq
      class << self
        def start!(namespace: "Sidekiq", interval: 60, client: nil)
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
          warn "Sidekiq metrics collection error: #{e.message}"
        end

        def collect_metrics
          return unless defined?(::Sidekiq)

          stats = ::Sidekiq::Stats.new
          @reporter.report("enqueued", stats.enqueued, unit: "Count")
          @reporter.report("processed", stats.processed, unit: "Count")
          @reporter.report("failed", stats.failed, unit: "Count")
          @reporter.report("scheduled_size", stats.scheduled_size, unit: "Count")
          @reporter.report("retry_size", stats.retry_size, unit: "Count")
          @reporter.report("dead_size", stats.dead_size, unit: "Count")
          @reporter.report("workers_size", stats.workers_size, unit: "Count")

          ::Sidekiq::Queue.all.each do |queue|
            dimensions = [{name: "QueueName", value: queue.name}]
            @reporter.report("queue_latency", queue.latency, unit: "Seconds", dimensions: dimensions)
            @reporter.report("queue_size", queue.size, unit: "Count", dimensions: dimensions)
          end
        end
      end
    end
  end
end
