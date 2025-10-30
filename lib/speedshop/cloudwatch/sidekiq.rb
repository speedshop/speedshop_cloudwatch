# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Sidekiq
      class << self
        def register(namespace: nil, reporter: Speedshop::Cloudwatch.reporter, process_metrics: true)
          @namespace = namespace || Speedshop::Cloudwatch.config.namespaces[:sidekiq]
          @reporter = reporter
          @process_metrics = process_metrics

          @reporter.register_collector do
            collect_metrics
          end

          setup_lifecycle_hooks if defined?(::Sidekiq)
        end

        private

        def setup_lifecycle_hooks
          ::Sidekiq.configure_server do |config|
            if defined?(::Sidekiq::Enterprise)
              config.on(:leader) do
                @reporter.start!
              end
            else
              config.on(:startup) do
                @reporter.start!
              end
            end

            config.on(:quiet) do
              @reporter.stop!
            end

            config.on(:shutdown) do
              @reporter.stop!
            end
          end
        end

        def collect_metrics
          return unless defined?(::Sidekiq)

          stats = ::Sidekiq::Stats.new
          processes = ::Sidekiq::ProcessSet.new.to_enum(:each).to_a

          @reporter.report("EnqueuedJobs", stats.enqueued, namespace: @namespace, unit: "Count")
          @reporter.report("ProcessedJobs", stats.processed, namespace: @namespace, unit: "Count")
          @reporter.report("FailedJobs", stats.failed, namespace: @namespace, unit: "Count")
          @reporter.report("ScheduledJobs", stats.scheduled_size, namespace: @namespace, unit: "Count")
          @reporter.report("RetryJobs", stats.retry_size, namespace: @namespace, unit: "Count")
          @reporter.report("DeadJobs", stats.dead_size, namespace: @namespace, unit: "Count")
          @reporter.report("Workers", stats.workers_size, namespace: @namespace, unit: "Count")
          @reporter.report("Processes", stats.processes_size, namespace: @namespace, unit: "Count")
          @reporter.report("DefaultQueueLatency", stats.default_queue_latency, namespace: @namespace, unit: "Seconds")

          capacity = calculate_capacity(processes)
          @reporter.report("Capacity", capacity, namespace: @namespace, unit: "Count")

          utilization = calculate_utilization(processes) * 100.0
          @reporter.report("Utilization", utilization, namespace: @namespace, unit: "Percent") unless utilization.nan?

          processes.group_by { |process| process["tag"] }.each do |(tag, tag_processes)|
            next if tag.nil?

            tag_dimensions = [{name: "Tag", value: tag}]
            tag_capacity = calculate_capacity(tag_processes)
            @reporter.report("Capacity", tag_capacity, namespace: @namespace, unit: "Count", dimensions: tag_dimensions)

            tag_utilization = calculate_utilization(tag_processes) * 100.0
            @reporter.report("Utilization", tag_utilization, namespace: @namespace, unit: "Percent", dimensions: tag_dimensions) unless tag_utilization.nan?
          end

          if @process_metrics
            processes.each do |process|
              process_utilization = process["busy"] / process["concurrency"].to_f * 100.0

              unless process_utilization.nan?
                process_dimensions = [{name: "Hostname", value: process["hostname"]}]

                if process["tag"] && !process["tag"].to_s.empty?
                  process_dimensions << {name: "Tag", value: process["tag"]}
                end

                @reporter.report("Utilization", process_utilization, namespace: @namespace, unit: "Percent", dimensions: process_dimensions)
              end
            end
          end

          queues = queues_to_monitor
          queues.each do |queue|
            dimensions = [{name: "QueueName", value: queue.name}]
            @reporter.report("QueueLatency", queue.latency, namespace: @namespace, unit: "Seconds", dimensions: dimensions)
            @reporter.report("QueueSize", queue.size, namespace: @namespace, unit: "Count", dimensions: dimensions)
          end
        end

        def queues_to_monitor
          configured_queues = Speedshop::Cloudwatch.config.sidekiq_queues
          all_queues = ::Sidekiq::Queue.all

          if configured_queues.nil? || configured_queues.empty?
            all_queues
          else
            all_queues.select { |queue| configured_queues.include?(queue.name) }
          end
        end

        def calculate_capacity(processes)
          processes.map { |process| process["concurrency"] }.sum
        end

        def calculate_utilization(processes)
          process_utilizations = processes.map do |process|
            process["busy"] / process["concurrency"].to_f
          end.reject(&:nan?)

          process_utilizations.sum / process_utilizations.size.to_f
        end
      end
    end
  end
end
