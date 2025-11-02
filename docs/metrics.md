# Metrics Reference

This document explains each metric collected by Speedshop::Cloudwatch, how it's calculated, and what it tells you about your application.

## Puma Metrics

### Workers
- **Unit:** Count
- **Source:** `Puma.stats_hash[:workers]`
- **Mode:** Cluster only (not reported in single mode)
- **Description:** Total number of workers (child processes) configured in Puma. This is a static configuration value that shows how many worker processes you've configured Puma to run.

### BootedWorkers
- **Unit:** Count
- **Source:** `Puma.stats_hash[:booted_workers]`
- **Mode:** Cluster only (not reported in single mode)
- **Description:** Number of worker processes currently running and ready to handle requests. Should match Workers count under normal operation. If lower, workers may be starting up or shutting down.

### OldWorkers
- **Unit:** Count
- **Source:** `Puma.stats_hash[:old_workers]`
- **Mode:** Cluster only (not reported in single mode)
- **Description:** Number of worker processes that are being phased out during a phased restart. Will be zero during normal operation and non-zero during deployments or restarts.

### Running
- **Unit:** Count
- **Dimensions:** WorkerIndex
- **Source:** `worker_stats[:running]`
- **Mode:** Both cluster and single (WorkerIndex=0 in single mode)
- **Description:** Number of threads currently processing requests in this worker. Compare against MaxThreads to understand thread utilization.

### Backlog
- **Unit:** Count
- **Dimensions:** WorkerIndex
- **Source:** `worker_stats[:backlog]`
- **Mode:** Both cluster and single (WorkerIndex=0 in single mode)
- **Description:** Number of requests waiting to be processed by this worker. It does not include the socket backlog (requests yet to be `accept`ed). Non-zero values indicate requests are arriving faster than threads can process them. Sustained backlog suggests you are over capacity.

### PoolCapacity
- **Unit:** Count
- **Dimensions:** WorkerIndex
- **Source:** `worker_stats[:pool_capacity]`
- **Mode:** Both cluster and single (WorkerIndex=0 in single mode)
- **Description:** Number of threads available to handle new requests in this worker. Calculated as MaxThreads minus Running threads. When this reaches zero, new requests queue in the backlog.

### MaxThreads
- **Unit:** Count
- **Dimensions:** WorkerIndex
- **Source:** `worker_stats[:max_threads]`
- **Mode:** Both cluster and single (WorkerIndex=0 in single mode)
- **Description:** Maximum number of threads configured for this worker. This is a static configuration value.

## Sidekiq Metrics

### EnqueuedJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.enqueued`
- **Description:** Total number of jobs currently enqueued across all queues. Jobs waiting to be processed by available workers.

### ProcessedJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.processed`
- **Description:** Cumulative count of all jobs successfully processed since Sidekiq started. Resets when Redis is cleared or Sidekiq statistics are reset.

### FailedJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.failed`
- **Description:** Cumulative count of all jobs that have failed since Sidekiq started. Includes jobs that exhausted retries and moved to dead queue.

### ScheduledJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.scheduled_size`
- **Description:** Number of jobs scheduled to run at a future time. These are not yet enqueued and will move to the enqueued state when their scheduled time arrives.

### RetryJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.retry_size`
- **Description:** Number of jobs in the retry queue. These are jobs that failed but have not exhausted their retry attempts.

### DeadJobs
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.dead_size`
- **Description:** Number of jobs in the dead queue. These jobs exhausted all retry attempts and are no longer being processed.

### Workers
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.workers_size`
- **Description:** Total number of worker threads currently processing jobs across all Sidekiq processes.

### Processes
- **Unit:** Count
- **Source:** `Sidekiq::Stats.new.processes_size`
- **Description:** Number of Sidekiq server processes currently running.

### DefaultQueueLatency
- **Unit:** Seconds
- **Source:** `Sidekiq::Stats.new.default_queue_latency`
- **Description:** Time the oldest job in the default queue has been waiting. Zero if the queue is empty.

### Capacity
- **Unit:** Count
- **Dimensions:** Tag (optional)
- **Source:** Sum of `process["concurrency"]` across processes
- **Description:** Total number of worker threads available across all Sidekiq processes. When reported with Tag dimension, shows capacity for processes with that specific tag.

### Utilization
- **Unit:** Percent
- **Dimensions:** Tag (optional), Hostname (optional)
- **Source:** Average of `busy / concurrency * 100` across processes
- **Description:** Average percentage of worker threads currently busy across processes. 100% means all workers are busy. Reported at three levels: overall (no dimensions), by tag, and by hostname.

### QueueLatency
- **Unit:** Seconds
- **Dimensions:** QueueName
- **Source:** `Sidekiq::Queue#latency`
- **Description:** Time the oldest job in this queue has been waiting. Zero if the queue is empty. High latency indicates jobs are backing up.

### QueueSize
- **Unit:** Count
- **Dimensions:** QueueName
- **Source:** `Sidekiq::Queue#size`
- **Description:** Number of jobs currently waiting in this queue. Growing queue size indicates jobs are arriving faster than they're being processed.

## Rack Metrics

### RequestQueueTime
- **Unit:** Milliseconds
- **Source:** `(Time.now.to_f * 1000) - HTTP_X_REQUEST_START`
- **Description:** Time a request spent waiting in the reverse proxy before reaching the application. Calculated from the `X-Request-Start` or `X-Queue-Start` header set by your reverse proxy (nginx, etc.). High values indicate requests are backing up before they even reach your application server, you need more capacity.

## ActiveJob Metrics

### QueueLatency
- **Unit:** Seconds
- **Dimensions:** QueueName
- **Source:** `Time.now.to_f - job.enqueued_at`
- **Description:** Time a job spent waiting in the queue before execution started. Measured when the job begins executing. Values are aggregated per queue into CloudWatch StatisticSets for each reporting interval.
