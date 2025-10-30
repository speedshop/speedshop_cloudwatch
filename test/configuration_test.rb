# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @config = Speedshop::Cloudwatch::Configuration.new
  end

  def test_has_default_interval
    assert_equal 60, @config.interval
  end

  def test_has_nil_client_by_default
    assert_nil @config.client
  end

  def test_has_all_integrations_enabled_by_default
    assert @config.enabled[:puma]
    assert @config.enabled[:sidekiq]
    assert @config.enabled[:rack]
    assert @config.enabled[:active_job]
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
    expected = [:JobQueueTime]
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

  def test_allows_disabling_integrations
    @config.enabled[:puma] = false
    refute @config.enabled[:puma]
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
end
