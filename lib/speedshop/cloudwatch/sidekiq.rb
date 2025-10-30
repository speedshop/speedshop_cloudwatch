# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Sidekiq
      class << self
        def register(namespace: nil, reporter: Speedshop::Cloudwatch.reporter, process_metrics: true)
          @namespace = namespace || Speedshop::Cloudwatch.config.namespaces[:sidekiq]
          @reporter = reporter
          @process_metrics = process_metrics
          @reporter.register_collector { collect_metrics }
          setup_lifecycle_hooks if defined?(::Sidekiq)
        end

        private

        def setup_lifecycle_hooks
          ::Sidekiq.configure_server do |config|
            config.on(defined?(::Sidekiq::Enterprise) ? :leader : :startup) { @reporter.start! }
            config.on(:quiet) { @reporter.stop! }
            config.on(:shutdown) { @reporter.stop! }
          end
        end

        def collect_metrics
          return unless defined?(::Sidekiq)
          stats = ::Sidekiq::Stats.new
          processes = ::Sidekiq::ProcessSet.new.to_a

          {EnqueuedJobs: stats.enqueued, ProcessedJobs: stats.processed, FailedJobs: stats.failed,
           ScheduledJobs: stats.scheduled_size, RetryJobs: stats.retry_size, DeadJobs: stats.dead_size,
           Workers: stats.workers_size, Processes: stats.processes_size}.each { |m, v| @reporter.report(m.to_s, v, namespace: @namespace, unit: "Count") }
          @reporter.report("DefaultQueueLatency", stats.default_queue_latency, namespace: @namespace, unit: "Seconds")

          report_utilization(processes)
          report_process_metrics(processes) if @process_metrics
          report_queue_metrics
        end

        def report_utilization(processes)
          capacity = processes.sum { |p| p["concurrency"] }
          @reporter.report("Capacity", capacity, namespace: @namespace, unit: "Count")

          utilization = avg_utilization(processes) * 100.0
          @reporter.report("Utilization", utilization, namespace: @namespace, unit: "Percent") unless utilization.nan?

          processes.group_by { |p| p["tag"] }.each do |tag, procs|
            next unless tag
            dims = [{name: "Tag", value: tag}]
            @reporter.report("Capacity", procs.sum { |p| p["concurrency"] }, namespace: @namespace, unit: "Count", dimensions: dims)
            util = avg_utilization(procs) * 100.0
            @reporter.report("Utilization", util, namespace: @namespace, unit: "Percent", dimensions: dims) unless util.nan?
          end
        end

        def report_process_metrics(processes)
          processes.each do |p|
            util = p["busy"] / p["concurrency"].to_f * 100.0
            next if util.nan?
            dims = [{name: "Hostname", value: p["hostname"]}]
            dims << {name: "Tag", value: p["tag"]} if p["tag"] && !p["tag"].to_s.empty?
            @reporter.report("Utilization", util, namespace: @namespace, unit: "Percent", dimensions: dims)
          end
        end

        def report_queue_metrics
          queues = Speedshop::Cloudwatch.config.sidekiq_queues
          queues = queues.nil? || queues.empty? ? ::Sidekiq::Queue.all : ::Sidekiq::Queue.all.select { |q| queues.include?(q.name) }
          queues.each do |q|
            dims = [{name: "QueueName", value: q.name}]
            @reporter.report("QueueLatency", q.latency, namespace: @namespace, unit: "Seconds", dimensions: dims)
            @reporter.report("QueueSize", q.size, namespace: @namespace, unit: "Count", dimensions: dims)
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
