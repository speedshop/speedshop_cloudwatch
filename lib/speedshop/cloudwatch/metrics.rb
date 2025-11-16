# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    Metric = Struct.new(:name, :unit, :description, :source, keyword_init: true)

    METRICS = {
      puma: [
        # Cluster-only metrics that report on the overall Puma process
        Metric.new(
          name: :Workers,
          unit: "Count",
          description: "Total number of workers (child processes) configured in " \
                       "Puma. This is a static configuration value.",
          source: "Puma.stats_hash[:workers]"
        ),
        Metric.new(
          name: :BootedWorkers,
          unit: "Count",
          description: "Number of worker processes currently running and ready to " \
                       "handle requests. Should match Workers count under normal " \
                       "operation.",
          source: "Puma.stats_hash[:booted_workers]"
        ),
        Metric.new(
          name: :OldWorkers,
          unit: "Count",
          description: "Number of worker processes being phased out during a " \
                       "restart. Zero during normal operation.",
          source: "Puma.stats_hash[:old_workers]"
        ),

        # Per-worker metrics (also available in single mode with WorkerIndex=0)
        Metric.new(
          name: :Running,
          unit: "Count",
          description: "Number of threads currently processing requests in this " \
                       "worker. Compare against MaxThreads to understand " \
                       "utilization.",
          source: "worker_stats[:running]"
        ),
        Metric.new(
          name: :Backlog,
          unit: "Count",
          description: "Number of requests waiting to be processed by this worker. " \
                       "Sustained backlog suggests over capacity.",
          source: "worker_stats[:backlog]"
        ),
        Metric.new(
          name: :PoolCapacity,
          unit: "Count",
          description: "Number of threads available to handle new requests. When " \
                       "this reaches zero, requests queue in the backlog.",
          source: "worker_stats[:pool_capacity]"
        ),
        Metric.new(
          name: :MaxThreads,
          unit: "Count",
          description: "Maximum number of threads configured for this worker. This " \
                       "is a static configuration value.",
          source: "worker_stats[:max_threads]"
        )
      ],

      sidekiq: [
        # Overall Sidekiq statistics
        Metric.new(
          name: :EnqueuedJobs,
          unit: "Count",
          description: "Total number of jobs currently enqueued across all queues, waiting to be processed.",
          source: "Sidekiq::Stats.new.enqueued"
        ),
        Metric.new(
          name: :ProcessedJobs,
          unit: "Count",
          description: "Cumulative count of all jobs successfully processed since Sidekiq started.",
          source: "Sidekiq::Stats.new.processed"
        ),
        Metric.new(
          name: :FailedJobs,
          unit: "Count",
          description: "Cumulative count of all jobs that have failed since Sidekiq started.",
          source: "Sidekiq::Stats.new.failed"
        ),
        Metric.new(
          name: :ScheduledJobs,
          unit: "Count",
          description: "Number of jobs scheduled to run at a future time. Will move " \
                       "to enqueued when their scheduled time arrives.",
          source: "Sidekiq::Stats.new.scheduled_size"
        ),
        Metric.new(
          name: :RetryJobs,
          unit: "Count",
          description: "Number of jobs in the retry queue. These jobs failed but " \
                       "have not exhausted their retry attempts.",
          source: "Sidekiq::Stats.new.retry_size"
        ),
        Metric.new(
          name: :DeadJobs,
          unit: "Count",
          description: "Number of jobs in the dead queue. These jobs exhausted all retry attempts.",
          source: "Sidekiq::Stats.new.dead_size"
        ),
        Metric.new(
          name: :Workers,
          unit: "Count",
          description: "Total number of worker threads currently processing jobs across all Sidekiq processes.",
          source: "Sidekiq::Stats.new.workers_size"
        ),
        Metric.new(
          name: :Processes,
          unit: "Count",
          description: "Number of Sidekiq server processes currently running.",
          source: "Sidekiq::Stats.new.processes_size"
        ),
        Metric.new(
          name: :DefaultQueueLatency,
          unit: "Seconds",
          description: "Time the oldest job in the default queue has been waiting. Zero if the queue is empty.",
          source: "Sidekiq::Stats.new.default_queue_latency"
        ),

        # Process-level metrics
        Metric.new(
          name: :Capacity,
          unit: "Count",
          description: "Total number of worker threads available across all Sidekiq " \
                       "processes. Can be tagged by process tag.",
          source: "Sum of process['concurrency'] across processes"
        ),
        Metric.new(
          name: :Utilization,
          unit: "Percent",
          description: "Average percentage of worker threads currently busy. 100% " \
                       "means all workers are busy. Can be reported by tag or " \
                       "hostname.",
          source: "Average of busy / concurrency * 100 across processes"
        ),

        # Queue-specific metrics
        Metric.new(
          name: :QueueLatency,
          unit: "Seconds",
          description: "Time the oldest job in this queue has been waiting. High " \
                       "latency indicates jobs are backing up.",
          source: "Sidekiq::Queue#latency"
        ),
        Metric.new(
          name: :QueueSize,
          unit: "Count",
          description: "Number of jobs currently waiting in this queue. Growing " \
                       "size indicates jobs arriving faster than processing.",
          source: "Sidekiq::Queue#size"
        )
      ],

      rack: [
        Metric.new(
          name: :RequestQueueTime,
          unit: "Milliseconds",
          description: "Time a request spent waiting in the reverse proxy before " \
                       "reaching the application. High values indicate requests " \
                       "backing up before reaching your application server.",
          source: "(Time.now.to_f * 1000) - HTTP_X_REQUEST_START"
        )
      ],

      active_job: [
        Metric.new(
          name: :QueueLatency,
          unit: "Seconds",
          description: "Time a job spent waiting in the queue before execution " \
                       "started. Values are aggregated into CloudWatch " \
                       "StatisticSets per reporting interval.",
          source: "Time.now.to_f - job.enqueued_at"
        )
      ]
    }.freeze
  end
end
