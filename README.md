# Speedshop::Cloudwatch

This gem helps integrate your Ruby application with AWS CloudWatch. There are integrations for **Puma**, **Rack**, **Sidekiq** and **ActiveJob**.

CloudWatch is unusually difficult to integrate with properly in Ruby, because the AWS library makes a synchronous HTTP request to AWS every time you record a metric. This is unlike the statsd or UDP-based models used by Datadog or other providers, which return more-or-less-instantaneously and are a lot less dangerous to use. Naively implementing this stuff yourself, you could end up adding 20-50ms of delay to your jobs or responses!

This library helps you avoid that latency by reporting to CloudWatch in a background thread.

This library supports **Ruby 2.7+, Sidekiq 7+, and Puma 6+**.

## Metrics

By default, only essential queue metrics are enabled. Puma metrics are disabled by default, and Sidekiq reports only `QueueLatency`.

For a full explanation of every metric, [read about them in the code.](./lib/speedshop/cloudwatch/metrics.rb)

```ruby
# Defaults. Copy and modify this list to customize.
config.metrics[:puma] = []  # Disabled by default

config.metrics[:sidekiq] = [:QueueLatency]  # Only queue latency by default

config.metrics[:rack] = [:RequestQueueTime]

config.metrics[:active_job] = [:QueueLatency]
```

To enable additional metrics, configure them explicitly:

```ruby
# Enable all Puma metrics
config.metrics[:puma] = [
  :Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads
]

# Enable additional Sidekiq metrics
config.metrics[:sidekiq] = [
  :EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs,
  :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity,
  :Utilization, :QueueLatency, :QueueSize
]
```

This gem is for **infrastructure and queue metrics**, not application performance metrics, like response times, job execution times, or error rates. Use your APM for that stuff.

## Installation

```ruby
gem 'speedshop-cloudwatch'
```

See each integration below for instructions on how to setup and configure that integration.

## Configuration

You'll need to [configure your CloudWatch API credentials](https://github.com/aws/aws-sdk-ruby?tab=readme-ov-file#configuration), which is usually done via ENV var.

### Environment Control

**By default, the reporter only runs in production.** The environment is detected from `RAILS_ENV`, `RACK_ENV`, or defaults to `"development"`.

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.enabled_environments = ["production", "staging"]
  config.environment = "staging" # optional override
end
```

### General Configuration

You can configure which metrics are reported, the CloudWatch namespace for each integration, and other settings:

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.client = Aws::CloudWatch::Client.new
  config.interval = 60

  # Optional: Custom logger (defaults to Rails.logger if available, otherwise STDOUT)
  config.logger = Logger.new(Rails.root.join("log", "cloudwatch.log"))

  # Customize which metrics to report (whitelist)
  # Puma metrics are disabled by default, enable them explicitly:
  config.metrics[:puma] = [:Workers, :BootedWorkers, :Running, :Backlog]
  # Sidekiq defaults to [:QueueLatency], add more as needed:
  config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency, :QueueSize]

  # Customize which Sidekiq queues to monitor (all queues by default)
  config.sidekiq_queues = ["critical", "default", "low_priority"]

  # Customize CloudWatch namespaces
  config.namespaces[:puma] = "MyApp/Puma"
  config.namespaces[:sidekiq] = "MyApp/Sidekiq"
  config.namespaces[:rack] = "MyApp/Rack"
  config.namespaces[:active_job] = "MyApp/ActiveJob"

  # Optional: Add custom dimensions to all metrics
  config.dimensions[:Env] = ENV["RAILS_ENV"] || "development"
end
```

> [!WARNING]
> Setting `config.interval` to less than 60 seconds automatically enables [high-resolution storage](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html#high-resolution-metrics) (1-second granularity) in CloudWatch, which incurs additional costs.

### Puma Integration

Add to your `config/puma.rb`:

```ruby
require_relative "../config/environment"

Speedshop::Cloudwatch.configure do |config|
  config.collectors << :puma
  # Enable Puma metrics (disabled by default)
  config.metrics[:puma] = [
    :Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads
  ]
end

# Start the reporter so Puma metrics are collected
Speedshop::Cloudwatch.start!
```

Collection runs in the master process and reports per-worker metrics (see below). This works correctly with both `preload_app true` and `false`, as well as single and cluster modes.

**Note:** Puma metrics are disabled by default. You must explicitly enable them in your configuration.

This reports the following metrics:

```
Workers - Number of workers configured (Count)
BootedWorkers - Number of workers currently booted (Count)
OldWorkers - Number of workers that are old/being phased out (Count)
Running - Number of threads currently running (Count) [per worker]
Backlog - Number of requests in the backlog (Count) [per worker]
PoolCapacity - Current thread pool capacity (Count) [per worker]
MaxThreads - Maximum number of threads configured (Count) [per worker]
```

Metrics marked [per worker] include a WorkerIndex dimension.

### Rack Integration

If you're using Rails, we'll automatically insert the correct middleware into the stack.

If you're using some other Rack-based framework, insert the `Speedshop::Cloudwatch::Rack` high up (i.e. first) in the stack.

You will need a reverse proxy, such as nginx, adding an `X-Request-Start` or `X-Queue-Start` header (containing the time since the Unix epoch in milliseconds) to incoming requests. See [New Relic's instructions](https://docs.newrelic.com/docs/apm/applications-menu/features/configure-request-queue-reporting/) for more about how to do this.

We report the following metrics:

```
RequestQueueTime - Time spent waiting in the request queue (Milliseconds)
```

### Sidekiq Integration

In Sidekiq server processes, this integration auto-registers lifecycle hooks. On startup, it adds the `:sidekiq` collector and starts the reporter (leader-only when using Sidekiq Enterprise).

If you're using Sidekiq as your ActiveJob adapter, prefer this integration instead of the ActiveJob integration.

By default, only `QueueLatency` is reported. To enable additional metrics, configure them explicitly:

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.metrics[:sidekiq] = [
    :EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs,
    :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity,
    :Utilization, :QueueLatency, :QueueSize
  ]
end
```

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
Utilization metrics include Tag and/or Hostname dimensions.

### ActiveJob integration

**Note: if you're using Sidekiq, just use that integration and do not include the ActiveJob module.**

In your ApplicationJob:

```ruby
include Speedshop::Cloudwatch::ActiveJob
```

We report the following metrics:

```
QueueLatency - Time job spent waiting in queue before execution (Seconds)
```

This metric includes QueueName dimension and is aggregated per interval using CloudWatch StatisticSets.

### Rails

When running in a Rails app we:

1. Automatically insert the Rack middleware at index 0 (skipped for console, runner, and common `assets:`/`db:` rake tasks).
2. Respect your configuration for enabled metrics and collectors. The reporter starts automatically the first time a metric is reported (e.g., via Rack middleware) or when you call `Speedshop::Cloudwatch.start!` yourself (e.g., in Puma or initializers).

If you want full control over these behaviors, add `require: false` to your Gemfile:

```ruby
gem 'speedshop-cloudwatch', require: false
```

Then manually require the core module without the railtie:

```ruby
# config/initializers/speedshop-cloudwatch.rb
require 'speedshop/cloudwatch'

# Insert middleware manually (if using Rack integration)
Rails.application.config.middleware.insert_before 0, Speedshop::Cloudwatch::Rack

Rails.application.configure do
  config.after_initialize do
    Speedshop::Cloudwatch.start!
  end
end
```

### Non-Rails Apps

For Rack apps (Sinatra, etc.):

- Insert `Speedshop::Cloudwatch::Rack` at the top of your middleware stack.
- Configure collectors and start the reporter during app boot.

Example config:

```ruby
require 'speedshop/cloudwatch'

Speedshop::Cloudwatch.configure do |config|
  # ...
end

Speedshop::Cloudwatch.start!
```

### Disabling Automatic Integration

You can disable the auto-integration of Sidekiq and Puma by not requiring them:

```ruby
gem 'speedshop-cloudwatch`, require: false
```

```ruby
# some_initializer.rb
require 'speedshop/cloudwatch'
require 'speedshop/cloudwatch/puma'
require 'speedshop/cloudwatch/active_job'
require 'speedshop/cloudwatch/rack'
# require 'speedshop/cloudwatch/sidekiq'
```

## Bibliography

This library was developed with reference to and inspiration from these excellent projects:

- [sidekiq-cloudwatchmetrics](https://github.com/sj26/sidekiq-cloudwatchmetrics) - Sidekiq CloudWatch metrics integration (portions adapted, see lib/speedshop/cloudwatch/sidekiq.rb)
- [puma-cloudwatch](https://github.com/boltops-tools/puma-cloudwatch) - Puma CloudWatch metrics reporter
- [judoscale-ruby](https://github.com/judoscale/judoscale-ruby) - Autoscaling metrics collection patterns
