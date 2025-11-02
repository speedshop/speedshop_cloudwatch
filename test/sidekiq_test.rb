# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/api"
require "connection_pool"

class SidekiqTest < SpeedshopCloudwatchTest
  class TestJob
    include Sidekiq::Job
    def perform
    end
  end

  def setup
    super
    Sidekiq.configure_client do |config|
      config.redis = {db: 15}
      config.logger = Logger.new(nil)
    end
    Sidekiq.configure_server do |config|
      config.redis = {db: 15}
      config.logger = Logger.new(nil)
    end
    begin
      Sidekiq.redis(&:flushdb)
    rescue RedisClient::CannotConnectError
      skip "Redis is not available; skipping Sidekiq tests"
    end
  end

  def teardown
    begin
      Sidekiq.redis(&:flushdb)
    rescue RedisClient::CannotConnectError
      # Ignore if Redis isn't available in this environment
    end
    super
  end

  def test_filters_queues_when_configured
    enqueue_test_jobs
    Speedshop::Cloudwatch.configure do |config|
      config.sidekiq_queues = ["critical", "default"]
    end

    queue_names = collect_sidekiq_queue_names
    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    refute_includes queue_names, "low_priority"
  end

  def test_monitors_all_queues_by_default
    enqueue_test_jobs
    Speedshop::Cloudwatch.configure do |config|
      config.sidekiq_queues = nil
    end

    queue_names = collect_sidekiq_queue_names
    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    assert_includes queue_names, "low_priority"
  end

  def test_collects_all_metrics_with_real_sidekiq_data
    reporter = Speedshop::Cloudwatch.reporter
    collector = Speedshop::Cloudwatch::Sidekiq::Collector.new
    collector.collect

    metric_names = reporter.queue.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "ProcessedJobs"
    assert_includes metric_names, "FailedJobs"
    assert_includes metric_names, "ScheduledJobs"
    assert_includes metric_names, "RetryJobs"
    assert_includes metric_names, "DeadJobs"
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "Processes"
    assert_includes metric_names, "DefaultQueueLatency"
    assert_includes metric_names, "Capacity"
  end

  def test_logs_error_when_collection_fails
    logger = TestDoubles::LoggerDouble.new

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    ::Sidekiq::Stats.stub(:new, -> { raise "boom" }) do
      collector = Speedshop::Cloudwatch::Sidekiq::Collector.new
      collector.collect
    end

    assert logger.error_logged?("Failed to collect Sidekiq metrics"), "Expected error to be logged"
  end

  private

  def enqueue_test_jobs
    TestJob.set(queue: "critical").perform_async
    TestJob.set(queue: "default").perform_async
    TestJob.set(queue: "low_priority").perform_async
  end

  def collect_sidekiq_queue_names
    reporter = Speedshop::Cloudwatch.reporter
    collector = Speedshop::Cloudwatch::Sidekiq::Collector.new
    collector.collect

    queue_metrics = reporter.queue.select do |m|
      m[:dimensions]&.any? { |d| d[:name] == "QueueName" }
    end
    queue_metrics.map { |m| m[:dimensions].find { |d| d[:name] == "QueueName" }[:value] }.uniq
  end
end
