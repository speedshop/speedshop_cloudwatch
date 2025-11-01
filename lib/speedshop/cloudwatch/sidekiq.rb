# frozen_string_literal: true

require "sidekiq/api"

module Speedshop
  module Cloudwatch
    module Sidekiq
      class << self
        def register(reporter:, process_metrics: true)
          @reporter = reporter
          ::Sidekiq.configure_server do |config|
            # Sidekiq Enterprise has a leader process; OSS does not.
            # Use :leader event for Enterprise to avoid duplicate reporting from all processes.
            # Use :startup event for OSS since it fires once per process.
            event = defined?(::Sidekiq::Enterprise) ? :leader : :startup

            config.on(event) do
              reporter.register_collector(:sidekiq) { collect_metrics(process_metrics: process_metrics) }
            end

            config.on(:quiet) do
              reporter.stop!
            end

            config.on(:shutdown) do
              reporter.stop!
            end
          end
        end

        private

        def collect_metrics(process_metrics:)
          stats = ::Sidekiq::Stats.new
          processes = ::Sidekiq::ProcessSet.new.to_a

          report_stats(stats)
          report_utilization(processes)
          report_process_metrics(processes) if process_metrics
          report_queue_metrics
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Sidekiq metrics: #{e.message}", e)
        end

        def report_stats(stats)
          {
            EnqueuedJobs: stats.enqueued, ProcessedJobs: stats.processed, FailedJobs: stats.failed,
            ScheduledJobs: stats.scheduled_size, RetryJobs: stats.retry_size, DeadJobs: stats.dead_size,
            Workers: stats.workers_size, Processes: stats.processes_size
          }.each { |m, v| @reporter.report(metric: m, value: v) }
          @reporter.report(metric: :DefaultQueueLatency, value: stats.default_queue_latency)
        end

        def report_utilization(processes)
          capacity = processes.sum { |p| p["concurrency"] }
          @reporter.report(metric: :Capacity, value: capacity)

          utilization = avg_utilization(processes) * 100.0
          @reporter.report(metric: :Utilization, value: utilization) unless utilization.nan?

          processes.group_by { |p| p["tag"] }.each do |tag, procs|
            next unless tag
            capacity = procs.sum { |p| p["concurrency"] }
            @reporter.report(metric: :Capacity, value: capacity, dimensions: {Tag: tag})
            util = avg_utilization(procs) * 100.0
            @reporter.report(metric: :Utilization, value: util, dimensions: {Tag: tag}) unless util.nan?
          end
        end

        def report_process_metrics(processes)
          processes.each do |p|
            next if p["concurrency"].zero?
            util = p["busy"] / p["concurrency"].to_f * 100.0
            dims = {Hostname: p["hostname"]}
            dims[:Tag] = p["tag"] if p["tag"] && !p["tag"].to_s.empty?
            @reporter.report(metric: :Utilization, value: util, dimensions: dims)
          end
        end

        def report_queue_metrics
          configured = Speedshop::Cloudwatch.config.sidekiq_queues
          # This whole thing is a bit expensive, both for us and for the Redis
          # instance. So, we're trying to minimize Redis load and work in this
          # whole section.
          all_queues = ::Sidekiq::Queue.all
          queues = (configured.nil? || configured.empty?) ? all_queues : all_queues.select { |q| configured.include?(q.name) }
          queues.each do |q|
            @reporter.report(metric: :QueueLatency, value: q.latency, dimensions: {QueueName: q.name})
            @reporter.report(metric: :QueueSize, value: q.size, dimensions: {QueueName: q.name})
          end
        end

        def avg_utilization(processes)
          utils = processes.map { |p| p["busy"] / p["concurrency"].to_f }.reject(&:nan?)
          utils.sum / utils.size.to_f
        end
      end
    end
  end
end
