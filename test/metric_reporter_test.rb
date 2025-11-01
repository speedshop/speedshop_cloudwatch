# frozen_string_literal: true

require "test_helper"

class MetricReporterTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch.config
    @config.namespaces[:test] = "TestApp"
    @config.metrics[:test] = [:test_metric, :another_metric, :custom_metric, :metric1, :metric2]
    @reporter = Speedshop::Cloudwatch::Reporter.instance
  end

  def teardown
    @reporter&.stop!
    super
  end

  def test_queues_metrics
    @reporter.report(metric: :test_metric, value: 42)
    @reporter.report(metric: :another_metric, value: 100)
  end

  def test_can_start_and_stop
    @reporter.start!
    @reporter.stop!
  end

  def test_filters_unregistered_puma_metrics
    @reporter.report(metric: :Workers, value: 4)

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_puma_metrics_whitelist
    @reporter.enable_integration(:puma)
    @config.metrics[:puma] = [:Workers]
    @reporter.report(metric: :Workers, value: 4)
    @reporter.report(metric: :BootedWorkers, value: 4)

    queue = @reporter.queue
    assert_equal 1, queue.size
    assert_equal "Workers", queue.first[:metric_name]
  end

  def test_filters_unregistered_sidekiq_metrics
    @reporter.report(metric: :EnqueuedJobs, value: 10)

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_sidekiq_metrics_whitelist
    @reporter.enable_integration(:sidekiq)
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency]
    @reporter.report(metric: :EnqueuedJobs, value: 10)
    @reporter.report(metric: :ProcessedJobs, value: 100)
    @reporter.report(metric: :QueueLatency, value: 5.2)

    queue = @reporter.queue
    assert_equal 2, queue.size
    metric_names = queue.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "QueueLatency"
    refute_includes metric_names, "ProcessedJobs"
  end

  def test_allows_unknown_namespaces
    @config.namespaces[:custom] = "CustomNamespace"
    @config.metrics[:custom] = [:my_custom_metric]
    @reporter.enable_integration(:custom)
    @reporter.report(metric: :my_custom_metric, value: 42)

    queue = @reporter.queue
    assert_equal 1, queue.size
  end

  def test_does_not_start_when_no_collectors_registered
    Speedshop::Cloudwatch::Integration.clear_integrations
    @reporter.start!

    assert_nil @reporter.thread
    refute @reporter.running
  end

  def test_started_returns_false_when_not_started
    refute @reporter.started?
  end

  def test_started_returns_true_when_started
    @reporter.enable_integration(:test)
    @reporter.start!
    assert @reporter.started?
  end

  def test_started_returns_false_after_stop
    @reporter.enable_integration(:test)
    @reporter.start!
    @reporter.stop!
    refute @reporter.started?
  end

  def test_start_is_idempotent
    @reporter.enable_integration(:test)
    @reporter.start!
    thread1 = @reporter.thread

    @reporter.start!
    thread2 = @reporter.thread

    assert_same thread1, thread2
  end

  def test_started_detects_pid_change
    @reporter.enable_integration(:test)
    @reporter.start!
    original_pid = @reporter.pid

    @reporter.pid = original_pid + 1

    refute @reporter.started?
  end

  def test_started_detects_dead_thread
    @reporter.enable_integration(:test)
    @reporter.start!
    @reporter.thread.kill
    @reporter.thread.join

    refute @reporter.started?
  end

  def test_adds_custom_dimensions_to_metrics
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    @reporter.enable_integration(:test)
    @reporter.report(metric: :test_metric, value: 42, dimensions: {Region: "us-east-1"})

    queue = @reporter.queue
    assert_equal 1, queue.size
    dimensions = queue.first[:dimensions]
    assert_equal 3, dimensions.size

    dimension_names = dimensions.map { |d| d[:name] }
    assert_includes dimension_names, "Region"
    assert_includes dimension_names, "ServiceName"
    assert_includes dimension_names, "Environment"

    service_dim = dimensions.find { |d| d[:name] == "ServiceName" }
    assert_equal "myservice-api", service_dim[:value]

    env_dim = dimensions.find { |d| d[:name] == "Environment" }
    assert_equal "production", env_dim[:value]
  end

  def test_works_without_custom_dimensions
    @reporter.enable_integration(:test)
    @reporter.report(metric: :test_metric, value: 42, dimensions: {Region: "us-east-1"})

    queue = @reporter.queue
    assert_equal 1, queue.size
    dimensions = queue.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "Region", dimensions.first[:name]
    assert_equal "us-east-1", dimensions.first[:value]
  end

  def test_custom_dimensions_with_no_metric_dimensions
    @config.dimensions = {ServiceName: "myservice-api"}
    @reporter.enable_integration(:test)
    @reporter.report(metric: :test_metric, value: 42)

    queue = @reporter.queue
    assert_equal 1, queue.size
    dimensions = queue.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "ServiceName", dimensions.first[:name]
    assert_equal "myservice-api", dimensions.first[:value]
  end

  def test_lazy_startup_on_first_report
    @reporter.enable_integration(:test)
    refute @reporter.started?

    @reporter.report(metric: :test_metric, value: 42)

    assert @reporter.started?
    assert @reporter.thread.alive?
  end

  def test_lazy_startup_does_not_double_start
    @reporter.enable_integration(:test)
    refute @reporter.started?

    @reporter.report(metric: :metric1, value: 1)
    thread1 = @reporter.thread

    @reporter.report(metric: :metric2, value: 2)
    thread2 = @reporter.thread

    assert_same thread1, thread2
  end

  def test_lazy_startup_restarts_after_stop
    @reporter.enable_integration(:test)
    @reporter.report(metric: :metric1, value: 1)
    assert @reporter.started?

    @reporter.stop!
    refute @reporter.started?

    @reporter.report(metric: :metric2, value: 2)
    assert @reporter.started?
  end

  def test_lazy_startup_with_unregistered_integration
    refute @reporter.started?

    @reporter.report(metric: :Workers, value: 4)

    refute @reporter.started?
    assert_empty @reporter.queue
  end
end
