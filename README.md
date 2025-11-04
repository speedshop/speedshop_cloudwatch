# Speedshop::Cloudwatch

This gem helps integrate your Ruby application with AWS CloudWatch. There are integrations for **Puma**, **Rack**, **Sidekiq** and **ActiveJob**.

CloudWatch is unusually difficult to integrate with properly in Ruby, because the AWS library makes a synchronous HTTP request to AWS every time you record a metric. This is unlike the statsd or UDP-based models used by Datadog or other providers, which return more-or-less-instantaneously and are a lot less dangerous to use. Naively implementing this stuff yourself, you could end up adding 20-50ms of delay to your jobs or responses!

This library helps you avoid that latency by reporting to CloudWatch in a background thread.

This library supports **Ruby 2.7+, Sidekiq 7+, and Puma 6+**.

## Metrics

If not configured, all metrics are enabled by default.

For a full explanation of every metric, [read our docs.](./docs/metrics.md)

```ruby
# Defaults. Copy and modify this list to customize.
config.metrics[:puma] = [
  :Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads
]

config.metrics[:sidekiq] = [
  :EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs,
  :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity,
  :Utilization, :QueueLatency, :QueueSize
]

config.metrics[:rack] = [:RequestQueueTime]

config.metrics[:active_job] = [:QueueLatency]
```

This gem is for **infrastructure and queue metrics**, not application performance metrics, like response times, job execution times, or error rates. Use your APM for that stuff.

## Installation

Add to your Gemfile:

```ruby
gem 'speedshop-cloudwatch', require: false
```

**Important:** Use `require: false` and explicitly require only the integrations you need. This gives you full control over which integrations are loaded.

Then require the integrations you need:

```ruby
# Option 1: Load all integrations (simplest, good for getting started)
require 'speedshop/cloudwatch/all'

# Option 2: Load only specific integrations (recommended for production)
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/puma'    # if using Puma
require 'speedshop/cloudwatch/sidekiq' # if using Sidekiq
require 'speedshop/cloudwatch/rack'    # if using Rack middleware
# require 'speedshop/cloudwatch/active_job' # if using ActiveJob (not with Sidekiq)
```

See each integration below for instructions on how to setup and configure that integration.

## Configuration

You'll need to [configure your CloudWatch API credentials](https://github.com/aws/aws-sdk-ruby?tab=readme-ov-file#configuration), which is usually done via ENV var.

You can configure which metrics are reported, the CloudWatch namespace for each integration, and other settings:

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.client = Aws::CloudWatch::Client.new
  config.interval = 60

  # Optional: Custom logger (defaults to Rails.logger if available, otherwise STDOUT)
  config.logger = Logger.new(Rails.root.join("log", "cloudwatch.log"))

  # Customize which metrics to report (whitelist)
  config.metrics[:puma] = [:Workers, :BootedWorkers, :Running, :Backlog]
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

### Puma Integration

Add to your `config/puma.rb`:

```ruby
require_relative "../config/environment"
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/puma'

Speedshop::Cloudwatch.configure do |config|
  config.collectors << :puma
end

# Start the reporter so Puma metrics are collected
Speedshop::Cloudwatch.start!
```

Collection runs in the master process and reports per-worker metrics (see below). This works correctly with both `preload_app true` and `false`, as well as single and cluster modes.

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

If you're using some other Rack-based framework, insert the `Speedshop::Cloudwatch::RackMiddleware` high up (i.e. first) in the stack.

You will need a reverse proxy, such as nginx, adding an `X-Request-Start` or `X-Queue-Start` header (containing the time since the Unix epoch in milliseconds) to incoming requests. See [New Relic's instructions](https://docs.newrelic.com/docs/apm/applications-menu/features/configure-request-queue-reporting/) for more about how to do this.

We report the following metrics:

```
RequestQueueTime - Time spent waiting in the request queue (Milliseconds)
```

### Sidekiq Integration

Require the Sidekiq integration in your initializer or where Sidekiq is configured:

```ruby
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/sidekiq'
```

This integration auto-registers lifecycle hooks. On startup (in server processes only), it adds the `:sidekiq` collector and starts the reporter (leader-only when using Sidekiq Enterprise).

If you're using Sidekiq as your ActiveJob adapter, prefer this integration instead of the ActiveJob integration.

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

**Note: if you're using Sidekiq, just use that integration and do not include the ActiveJob module.**

First, require the ActiveJob integration:

```ruby
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/active_job'
```

Then in your ApplicationJob:

```ruby
include Speedshop::Cloudwatch::ActiveJob
```

We report the following metrics:

```
QueueLatency - Time job spent waiting in queue before execution (Seconds)
```

This metric includes QueueName dimension and is aggregated per interval using CloudWatch StatisticSets.

### Rails

**Automatic behavior (requires `speedshop/cloudwatch/all`):**

If you require `speedshop/cloudwatch/all`, the Railtie will automatically insert the Rack middleware at index 0 (skipped for console, runner, and common `assets:`/`db:` rake tasks).

```ruby
# Gemfile
gem 'speedshop-cloudwatch', require: false

# config/initializers/speedshop_cloudwatch.rb
require 'speedshop/cloudwatch/all'

Speedshop::Cloudwatch.configure do |config|
  # your config here
end
```

**Manual control (recommended for production):**

For fine-grained control, require only the integrations you need and configure them explicitly:

```ruby
# Gemfile
gem 'speedshop-cloudwatch', require: false

# config/initializers/speedshop_cloudwatch.rb
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/rack'    # loads middleware class but doesn't auto-insert

# Insert middleware manually
Rails.application.config.middleware.insert_before 0, Speedshop::Cloudwatch::RackMiddleware

Speedshop::Cloudwatch.configure do |config|
  # your config here
end

# Start reporter after initialization
Rails.application.config.after_initialize do
  Speedshop::Cloudwatch.start!
end
```

### Non-Rails Apps

For Rack apps (Sinatra, etc.):

- Require the integrations you need
- Insert `Speedshop::Cloudwatch::RackMiddleware` at the top of your middleware stack
- Configure collectors and start the reporter during app boot

Example config:

```ruby
require 'speedshop/cloudwatch/core'
require 'speedshop/cloudwatch/rack'

# Insert middleware
use Speedshop::Cloudwatch::RackMiddleware

Speedshop::Cloudwatch.configure do |config|
  # your config here
end

Speedshop::Cloudwatch.start!
```


### Disabling Integrations

The best way to disable an integration is to not require it:

- **Puma:** Do not `require 'speedshop/cloudwatch/puma'` or add `:puma` to `config.collectors`.
- **Sidekiq:** Do not `require 'speedshop/cloudwatch/sidekiq'`.
- **Rack:** Do not `require 'speedshop/cloudwatch/rack'` or insert the middleware.
- **ActiveJob:** Do not `require 'speedshop/cloudwatch/active_job'` or include the module in your jobs.

You can also disable specific metrics by setting them to an empty array:

```ruby
Speedshop::Cloudwatch.configure do |config|
  config.metrics[:rack] = []  # Disable all Rack metrics
end
```
