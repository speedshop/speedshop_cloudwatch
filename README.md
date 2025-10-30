# Speedshop::Cloudwatch

This gem helps integrate your Ruby application with AWS Cloudwatch.

* **Puma** will report statistics (like busy_threads) as metrics.
* **Rack** applications will report request queue time as metrics, via a Rack middleware.
* **Sidekiq** applications report queue latencies as metrics, using a background reporting thread.
* Rails apps using **ActiveJob** report queue latencies with the `around_perform` callback.

Cloudwatch is unusually difficult to integrate with properly in Ruby, because the AWS library simply makes a straight-up synchronous HTTP request to AWS every time you record a metric. This is unlike the statsd or UDP-based models used by Datadog or other providers, which return more-or-less-instantaneously and are a lot less dangerous to use. Naively implementing this stuff yourself, you could end up adding 20-50ms of delay to your jobs or responses.

This library helps you avoid that latency by reporting to Cloudwatch in a background thread.

## What This Gem Does NOT Track

This gem focuses on **infrastructure and queue metrics**, not application performance metrics. Specifically:

- **No request/response times** - Use your APM tool (New Relic, Scout, Datadog APM, etc.) for this
- **No job execution times** - Use your APM tool for detailed job performance tracking
- **No error rates** - Use your APM or error tracking tool (Sentry, Rollbar, etc.)

This gem tracks queue depths, latencies, and resource utilization - metrics that help you understand if you need to scale your infrastructure. For detailed application performance and error tracking, use dedicated APM tools.

## Installation

```
gem `speedshop_cloudwatch`
```

## Configuration

You can configure which integrations are enabled, which metrics are reported, and the CloudWatch namespace for each integration:

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.client = Aws::CloudWatch::Client.new
  config.interval = 60

  # Optional: Custom logger (defaults to Rails.logger if available, otherwise STDOUT)
  config.logger = Logger.new(Rails.root.join("log", "cloudwatch.log"))

  # Disable an entire integration
  config.enabled[:rack] = false

  # Customize which metrics to report (whitelist)
  config.metrics[:puma] = [:workers, :booted_workers, :running, :backlog]
  config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency, :QueueSize]

  # Customize which Sidekiq queues to monitor (all queues by default)
  config.sidekiq_queues = ["critical", "default", "low_priority"]

  # Customize CloudWatch namespaces
  config.namespaces[:puma] = "MyApp/Puma"
  config.namespaces[:sidekiq] = "MyApp/Sidekiq"
  config.namespaces[:rack] = "MyApp/Rack"
  config.namespaces[:active_job] = "MyApp/ActiveJob"
end
```

### Default Metrics

If not configured, all metrics are enabled by default. Here are the default metric lists you can copy and customize:

**Puma:**
```ruby
config.metrics[:puma] = [:workers, :booted_workers, :old_workers, :running, :backlog, :pool_capacity, :max_threads]
```

**Sidekiq:**
```ruby
config.metrics[:sidekiq] = [:EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs, :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity, :Utilization, :QueueLatency, :QueueSize]
```

**Rack:**
```ruby
config.metrics[:rack] = [:request_queue_time]
```

**ActiveJob:**
```ruby
config.metrics[:active_job] = [:job_queue_time]
```

### Puma Integration

Add to your `config/puma.rb`:

```ruby
before_fork do
  Speedshop::Cloudwatch::Puma.start!
end
```

This then reports the following metrics:

```
workers - Number of workers configured (Count)
booted_workers - Number of workers currently booted (Count)
old_workers - Number of workers that are old/being phased out (Count)
running - Number of threads currently running (Count) [per worker]
backlog - Number of requests in the backlog (Count) [per worker]
pool_capacity - Current thread pool capacity (Count) [per worker]
max_threads - Maximum number of threads configured (Count) [per worker]
```

Metrics marked [per worker] include a WorkerIndex dimension.

### Rack Integration

If you're using Rails, we'll automatically insert the correct middleware into the stack.

If you're using some other Rack-based framework, insert the `Speedshop::Cloudwatch::RackMiddleware` high up (i.e. first) in the stack.

You will need to have a reverse proxy, such as nginx, adding `X-Request-Queue-Start` headers (containing the time since the Unix epoch in milliseconds) to incoming requests. See [New Relic's instructions](https://docs.newrelic.com/docs/apm/applications-menu/features/configure-request-queue-reporting/) for more about how to do this.

We report the following metrics:

```
request_queue_time - Time spent waiting in the request queue (Milliseconds)
```

### Sidekiq Integration

In your sidekiq.rb or other initializer:

```ruby
Speedshop::Cloudwatch::Sidekiq.start!
```

If you're using Speedshop with ActiveJob, you should use this integration rather than the ActiveJob integration.

We report the following metrics:

```
EnqueuedJobs - Number of jobs currently enqueued (Count)
ProcessedJobs - Total number of jobs processed (Count)
FailedJobs - Total number of failed jobs (Count)
ScheduledJobs - Number of scheduled jobs (Count)
RetryJobs - Number of jobs in retry queue (Count)
DeadJobs - Number of dead jobs (Count)
Workers - Number of Sidekiq workers (Count)
Processes - Number of Sidekiq processes (Count)
DefaultQueueLatency - Latency for the default queue (Seconds)
Capacity - Total concurrency across all processes (Count)
Utilization - Average utilization across all processes (Percent)
QueueLatency - Latency for each queue (Seconds) [per queue]
QueueSize - Size of each queue (Count) [per queue]
```

Metrics marked [per queue] include a QueueName dimension.
Capacity and Utilization metrics may include Tag and/or Hostname dimensions.

### ActiveJob integration

**Note: if you're using Sidekiq, just use that integration, and don't do the following!**

In your ApplicationJob:

```ruby
include Speedshop::Cloudwatch::ActiveJob
```

We report the following metrics:

```
job_queue_time - Time job spent waiting in queue before execution (Seconds)
```

This metric includes JobClass and QueueName dimensions.
