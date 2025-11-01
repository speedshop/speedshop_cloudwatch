# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch::Config.instance
  end

  def test_has_default_interval
    reset_singletons
    config = Speedshop::Cloudwatch::Config.instance
    assert_equal 60, config.interval
  end

  def test_has_default_client
    assert_instance_of Aws::CloudWatch::Client, @config.client
  end

  def test_has_default_puma_metrics
    expected = [:Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads]
    assert_equal expected, @config.metrics[:puma]
  end

  def test_has_default_sidekiq_metrics
    expected = [:EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs, :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity, :Utilization, :QueueLatency, :QueueSize]
    assert_equal expected, @config.metrics[:sidekiq]
  end

  def test_has_default_rack_metrics
    expected = [:RequestQueueTime]
    assert_equal expected, @config.metrics[:rack]
  end

  def test_has_default_active_job_metrics
    expected = [:QueueLatency]
    assert_equal expected, @config.metrics[:active_job]
  end

  def test_has_default_puma_namespace
    assert_equal "Puma", @config.namespaces[:puma]
  end

  def test_has_default_sidekiq_namespace
    assert_equal "Sidekiq", @config.namespaces[:sidekiq]
  end

  def test_has_default_rack_namespace
    assert_equal "Rack", @config.namespaces[:rack]
  end

  def test_has_default_active_job_namespace
    assert_equal "ActiveJob", @config.namespaces[:active_job]
  end

  def test_sidekiq_queues_defaults_to_nil
    assert_nil @config.sidekiq_queues
  end

  def test_has_default_logger
    assert_kind_of Logger, @config.logger
  end

  def test_allows_setting_custom_interval
    @config.interval = 120
    assert_equal 120, @config.interval
  end

  def test_allows_setting_custom_client
    client = Object.new
    @config.client = client
    assert_same client, @config.client
  end

  def test_allows_customizing_metrics
    @config.metrics[:puma] = [:Workers, :Running]
    assert_equal [:Workers, :Running], @config.metrics[:puma]
  end

  def test_allows_customizing_namespaces
    @config.namespaces[:puma] = "MyApp/Puma"
    assert_equal "MyApp/Puma", @config.namespaces[:puma]
  end

  def test_allows_setting_sidekiq_queues
    @config.sidekiq_queues = ["critical", "default"]
    assert_equal ["critical", "default"], @config.sidekiq_queues
  end

  def test_allows_setting_custom_logger
    custom_logger = Logger.new(nil)
    @config.logger = custom_logger
    assert_same custom_logger, @config.logger
  end

  def test_dimensions_defaults_to_empty_hash
    assert_equal({}, @config.dimensions)
  end

  def test_allows_setting_custom_dimensions
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    assert_equal({ServiceName: "myservice-api", Environment: "production"}, @config.dimensions)
  end
end
