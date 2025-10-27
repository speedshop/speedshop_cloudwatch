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
TODO: Fill this in based on Puma.stats output
```

### Rack Integration

If you're using Rails, we'll automatically insert the correct middleware into the stack.

If you're using some other Rack-based framework, insert the `Speedshop::Cloudwatch::RackMiddleware` high up (i.e. first) in the stack.

You will need to have a reverse proxy, such as nginx, adding `X-Request-Queue-Start` headers (containing the time since the Unix epoch in milliseconds) to incoming requests. See [New Relic's instructions](https://docs.newrelic.com/docs/apm/applications-menu/features/configure-request-queue-reporting/) for more about how to do this.

We report the following metrics:

```
TODO: fill in
```

### Sidekiq Integration

In your sidekiq.rb or other initializer:

```ruby
Speedshop::Cloudwatch::Sidekiq.start!
```

If you're using Speedshop with ActiveJob, you should use this integration rather than the ActiveJob integration.

We report the following metrics:

```
TODO: fill in
```

### ActiveJob integration

In your ApplicationJob:

```ruby
include Speedshop::Cloudwatch::ActiveJob
```

We report the following metrics:

```
TODO: fill in
```
