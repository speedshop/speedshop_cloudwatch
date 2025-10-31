# Speedshop::Cloudwatch Smoketest

This is a full-stack integration test for the speedshop_cloudwatch gem. It tests all four integrations (Puma, Rack, Sidekiq, and ActiveJob) against a real Rails application.

## What It Tests

The smoketest verifies that all expected CloudWatch metrics are captured:

**Puma:** Workers, BootedWorkers, OldWorkers, Running, Backlog, PoolCapacity, MaxThreads

**Rack:** RequestQueueTime

**Sidekiq:** EnqueuedJobs, ProcessedJobs, FailedJobs, ScheduledJobs, RetryJobs, DeadJobs, Workers, Processes, DefaultQueueLatency, Capacity, Utilization, QueueLatency, QueueSize

**ActiveJob:** QueueLatency

## How It Works

1. Starts a Redis server
2. Starts a Rails application with Puma in cluster mode (2 workers)
3. Starts Sidekiq with full Redis integration
4. Uses WebMock to intercept all AWS CloudWatch API calls
5. Generates test traffic (HTTP requests, Sidekiq jobs, ActiveJob tasks)
6. Runs for 2 minutes to allow multiple metric collection intervals
7. Verifies that all expected metrics were sent to CloudWatch
8. Fails with detailed error messages if any metrics are missing

## Prerequisites

- Ruby 3.4.7
- Redis server installed
- gum CLI tool (for pretty TUI output): `brew install gum`

## Versions

- Ruby 3.4.7
- Rails 8.0
- Puma 7.x
- Sidekiq 8.x

## Running the Smoketest

```fish
./run_smoketest.fish
```

The script will:
- Install dependencies
- Start all services
- Generate test traffic
- Wait for metrics collection
- Stop all services
- Verify captured metrics
- Report success or failure

## Configuration

The smoketest uses:
- Ruby 3.4.7
- Rails 8.0
- Puma 7.x: Cluster mode with 2 workers
- Sidekiq 8.x: Full setup with Redis
- ActiveJob: Inline adapter (separate from Sidekiq)
- Metrics collection interval: 15 seconds (faster than production default of 60s)

## Output

The verification script (`verify_metrics.rb`) generates a detailed report showing:
- Which metrics were captured
- Which metrics are missing (if any)
- Total API calls made
- Summary statistics

## Captured Metrics

All CloudWatch API requests are captured in `tmp/captured_metrics.json` for inspection and debugging.
