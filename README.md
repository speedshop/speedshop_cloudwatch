# Speedshop::Cloudwatch

This gem helps integrate your Ruby application with AWS Cloudwatch.

* **Puma** will report statistics (like busy_threads) as metrics.
* **Rack** applications will report request queue time as metrics, via a Rack middleware.
* **Sidekiq** applications report queue latencies as metrics, using a background reporting thread.
* Rails apps using **ActiveJob** report queue latencies with the `around_perform` callback.

Cloudwatch is unusually difficult to integrate with properly in Ruby, because the AWS library simply makes a straight-up synchronous HTTP request to AWS every time you record a metric. This is unlike the statsd or UDP-based models used by Datadog or other providers, which return more-or-less-instantaneously and are a lot less dangerous to use. Naively implementing this stuff yourself, you could end up adding 20-50ms of delay to your jobs or responses.

This library helps you avoid that latency by reporting to Cloudwatch in a  background thread.

## Installation

```
gem `speedshop_cloudwatch`
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
enqueued - Number of jobs currently enqueued (Count)
processed - Total number of jobs processed (Count)
failed - Total number of failed jobs (Count)
scheduled_size - Number of scheduled jobs (Count)
retry_size - Number of jobs in retry queue (Count)
dead_size - Number of dead jobs (Count)
workers_size - Number of Sidekiq workers (Count)
queue_latency - Latency for each queue (Seconds) [per queue]
queue_size - Size of each queue (Count) [per queue]
```

Metrics marked [per queue] include a QueueName dimension.

### ActiveJob integration

In your ApplicationJob:

```ruby
include Speedshop::Cloudwatch::ActiveJob
```

We report the following metrics:

```
job_queue_time - Time job spent waiting in queue before execution (Seconds)
job_execution_time - Time spent executing the job (Seconds)
```

Both metrics include JobClass and QueueName dimensions.
