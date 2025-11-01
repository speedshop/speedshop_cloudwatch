# frozen_string_literal: true

require "test_helper"

class MetricReporterTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch.config
    @config.namespaces[:test] = "TestApp"
    @config.metrics[:test] = [:test_metric, :another_metric, :custom_metric, :metric1, :metric2]
    @reporter = Speedshop::Cloudwatch::MetricReporter.new(config: @config)
  end

  def teardown
    @reporter&.stop!
    super
  end

  def test_queues_metrics
    @reporter.report("test_metric", 42, integration: :test)
    @reporter.report("another_metric", 100, integration: :test, unit: "Count")
  end

  def test_can_start_and_stop
    @reporter.start!
    @reporter.stop!
  end

  def test_filters_unregistered_puma_metrics
    @reporter.report("Workers", 4, integration: :puma)

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_puma_metrics_whitelist
    @reporter.register_collector(:puma) {}
    @config.metrics[:puma] = [:Workers]
    @reporter.report("Workers", 4, integration: :puma)
    @reporter.report("BootedWorkers", 4, integration: :puma)

    queue = @reporter.queue
    assert_equal 1, queue.size
    assert_equal "Workers", queue.first[:metric_name]
  end

  def test_filters_unregistered_sidekiq_metrics
    @reporter.report("EnqueuedJobs", 10, integration: :sidekiq)

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_sidekiq_metrics_whitelist
    @reporter.register_collector(:sidekiq) {}
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency]
    @reporter.report("EnqueuedJobs", 10, integration: :sidekiq)
    @reporter.report("ProcessedJobs", 100, integration: :sidekiq)
    @reporter.report("QueueLatency", 5.2, integration: :sidekiq)

    queue = @reporter.queue
    assert_equal 2, queue.size
    metric_names = queue.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "QueueLatency"
    refute_includes metric_names, "ProcessedJobs"
  end

  def test_allows_unknown_namespaces
    @config.namespaces[:custom] = "CustomNamespace"
    @config.metrics[:custom] = [:custom_metric]
    @reporter.register_collector(:custom) {}
    @reporter.report("custom_metric", 42, integration: :custom)

    queue = @reporter.queue
    assert_equal 1, queue.size
  end

  def test_does_not_start_when_no_collectors_registered
    @reporter.start!

    assert_nil @reporter.thread
    refute @reporter.running
  end

  def test_started_returns_false_when_not_started
    refute @reporter.started?
  end

  def test_started_returns_true_when_started
    @reporter.register_collector(:test) {}
    @reporter.start!
    assert @reporter.started?
  end

  def test_started_returns_false_after_stop
    @reporter.register_collector(:test) {}
    @reporter.start!
    @reporter.stop!
    refute @reporter.started?
  end

  def test_start_is_idempotent
    @reporter.register_collector(:test) {}
    @reporter.start!
    thread1 = @reporter.thread

    @reporter.start!
    thread2 = @reporter.thread

    assert_same thread1, thread2
  end

  def test_started_detects_pid_change
    @reporter.register_collector(:test) {}
    @reporter.start!
    original_pid = @reporter.instance_variable_get(:@pid)

    @reporter.instance_variable_set(:@pid, original_pid + 1)

    refute @reporter.started?
  end

  def test_started_detects_dead_thread
    @reporter.register_collector(:test) {}
    @reporter.start!
    @reporter.instance_variable_get(:@thread).kill
    @reporter.instance_variable_get(:@thread).join

    refute @reporter.started?
  end

  def test_adds_custom_dimensions_to_metrics
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    @reporter.register_collector(:test) {}
    @reporter.report("test_metric", 42, integration: :test, dimensions: [{name: "Region", value: "us-east-1"}])

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
    @reporter.register_collector(:test) {}
    @reporter.report("test_metric", 42, integration: :test, dimensions: [{name: "Region", value: "us-east-1"}])

    queue = @reporter.queue
    assert_equal 1, queue.size
    dimensions = queue.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "Region", dimensions.first[:name]
    assert_equal "us-east-1", dimensions.first[:value]
  end

  def test_custom_dimensions_with_no_metric_dimensions
    @config.dimensions = {ServiceName: "myservice-api"}
    @reporter.register_collector(:test) {}
    @reporter.report("test_metric", 42, integration: :test)

    queue = @reporter.queue
    assert_equal 1, queue.size
    dimensions = queue.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "ServiceName", dimensions.first[:name]
    assert_equal "myservice-api", dimensions.first[:value]
  end

  def test_lazy_startup_on_first_report
    @reporter.register_collector(:test) {}
    refute @reporter.started?

    @reporter.report("test_metric", 42, integration: :test)

    assert @reporter.started?
    assert @reporter.thread.alive?
  end

  def test_lazy_startup_does_not_double_start
    @reporter.register_collector(:test) {}
    refute @reporter.started?

    @reporter.report("metric1", 1, integration: :test)
    thread1 = @reporter.thread

    @reporter.report("metric2", 2, integration: :test)
    thread2 = @reporter.thread

    assert_same thread1, thread2
  end

  def test_lazy_startup_restarts_after_stop
    @reporter.register_collector(:test) {}
    @reporter.report("metric1", 1, integration: :test)
    assert @reporter.started?

    @reporter.stop!
    refute @reporter.started?

    @reporter.report("metric2", 2, integration: :test)
    assert @reporter.started?
  end

  def test_lazy_startup_with_unregistered_integration
    refute @reporter.started?

    @reporter.report("Workers", 4, integration: :puma)

    refute @reporter.started?
    assert_empty @reporter.queue
  end
end
