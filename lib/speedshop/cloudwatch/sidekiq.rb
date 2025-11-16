# frozen_string_literal: true

require "sidekiq/api"

module Speedshop
  module Cloudwatch
    class Sidekiq
      def collect
        stats = ::Sidekiq::Stats.new
        processes = ::Sidekiq::ProcessSet.new.to_a

        report_stats(stats)
        report_utilization(processes)
        report_process_metrics(processes)
        report_queue_metrics
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Sidekiq metrics: #{e.message}", e)
      end

      class << self
        def setup_lifecycle_hooks
          ::Sidekiq.configure_server do |config|
            setup_start_hook(config)
            setup_stop_hooks(config)
          end
        end

        private

        def setup_start_hook(config)
          hook = enterprise? ? :leader : :startup
          config.on(hook) { enable_and_start }
        end

        def setup_stop_hooks(config)
          config.on(:quiet) { Speedshop::Cloudwatch.stop! }
          config.on(:shutdown) { Speedshop::Cloudwatch.stop! }
        end

        def enterprise?
          defined?(Sidekiq::Enterprise)
        end

        def enable_and_start
          Speedshop::Cloudwatch.configure { |c| c.collectors << :sidekiq }
          Speedshop::Cloudwatch.start!
        end
      end

      private

      def reporter
        Speedshop::Cloudwatch.reporter
      end

      def report_stats(stats)
        {
          EnqueuedJobs: stats.enqueued, ProcessedJobs: stats.processed, FailedJobs: stats.failed,
          ScheduledJobs: stats.scheduled_size, RetryJobs: stats.retry_size, DeadJobs: stats.dead_size,
          Workers: stats.workers_size, Processes: stats.processes_size,
          DefaultQueueLatency: stats.default_queue_latency
        }.each { |m, v| reporter.report(metric: m, value: v, integration: :sidekiq) }
      end

      def report_utilization(processes)
        report_global_metrics(processes)
        report_tagged_metrics(processes)
      end

      def report_process_metrics(processes)
        processes.each { |p| report_single_process(p) }
      end

      def report_queue_metrics
        queues_to_monitor.each { |q| report_queue(q) }
      end

      def report_global_metrics(processes)
        report_capacity(processes)
        report_utilization_metric(processes)
      end

      def report_tagged_metrics(processes)
        processes.group_by { |p| p["tag"] }.each do |tag, procs|
          next unless tag

          report_capacity(procs, tag: tag)
          report_utilization_metric(procs, tag: tag)
        end
      end

      def report_capacity(processes, tag: nil)
        capacity = processes.sum { |p| p["concurrency"] }
        dims = tag ? {Tag: tag} : {}
        reporter.report(metric: :Capacity, value: capacity, dimensions: dims)
      end

      def report_utilization_metric(processes, tag: nil)
        util = avg_utilization(processes) * 100.0
        return if util.nan?

        dims = tag ? {Tag: tag} : {}
        reporter.report(metric: :Utilization, value: util, dimensions: dims)
      end

      def report_single_process(process)
        return if process["concurrency"].zero?

        util = process["busy"] / process["concurrency"].to_f * 100.0
        reporter.report(metric: :Utilization, value: util, dimensions: process_dimensions(process))
      end

      def process_dimensions(process)
        {Hostname: process["hostname"]}.tap do |dims|
          tag = process["tag"]
          dims[:Tag] = tag if tag && !tag.to_s.empty?
        end
      end

      def queues_to_monitor
        configured = Speedshop::Cloudwatch.config.sidekiq_queues
        all = ::Sidekiq::Queue.all
        (configured.nil? || configured.empty?) ? all : all.select { |q| configured.include?(q.name) }
      end

      def report_queue(queue)
        dims = {QueueName: queue.name}
        reporter.report(metric: :QueueLatency, value: queue.latency, dimensions: dims)
        reporter.report(metric: :QueueSize, value: queue.size, dimensions: dims)
      end

      def avg_utilization(processes)
        utils = processes.map { |p| p["busy"] / p["concurrency"].to_f }.reject(&:nan?)
        utils.sum / utils.size.to_f
      end
    end
  end
end

Speedshop::Cloudwatch::Sidekiq.setup_lifecycle_hooks
