# frozen_string_literal: true

require "test_helper"

class ReporterTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch.config
    @config.namespaces[:test] = "TestApp"
    @config.metrics[:test] = [:test_metric, :another_metric, :custom_metric, :metric1, :metric2]
    @reporter = Speedshop::Cloudwatch.reporter
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

  def test_respects_puma_metrics_whitelist
    @config.metrics[:puma] = [:Workers]
    @reporter.report(metric: :Workers, value: 4)
    @reporter.report(metric: :BootedWorkers, value: 4)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    assert_equal "Workers", metrics.first[:metric_name]
  end

  def test_respects_sidekiq_metrics_whitelist
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency]
    @reporter.report(metric: :EnqueuedJobs, value: 10)
    @reporter.report(metric: :ProcessedJobs, value: 100)
    @reporter.report(metric: :QueueLatency, value: 5.2)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 2, metrics.size
    metric_names = metrics.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "QueueLatency"
    refute_includes metric_names, "ProcessedJobs"
  end

  def test_allows_unknown_namespaces
    @config.namespaces[:custom] = "CustomNamespace"
    @config.metrics[:custom] = [:my_custom_metric]
    @reporter.report(metric: :my_custom_metric, value: 42)
    @reporter.start!
    @reporter.flush_now!

    assert_equal 1, @test_client.metric_count
  end

  def test_started_returns_false_when_not_started
    refute @reporter.started?
  end

  def test_started_returns_true_when_started
    @reporter.start!
    assert @reporter.started?
  end

  def test_started_returns_false_after_stop
    @reporter.start!
    @reporter.stop!
    refute @reporter.started?
  end

  def test_start_is_idempotent
    @reporter.start!
    @reporter.start!
    sleep(0.01)
    assert_equal 1, Thread.list.count { |t| t.name == "scw_reporter" }
  end

  def test_started_detects_dead_thread
    @reporter.start!
    sleep(0.01)
    thread = Thread.list.find { |t| t.name == "scw_reporter" }
    thread.kill && thread.join

    refute @reporter.started?
  end

  def test_adds_custom_dimensions_to_metrics
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    @reporter.report(metric: :test_metric, value: 42, dimensions: {Region: "us-east-1"})
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
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
    @reporter.report(metric: :test_metric, value: 42, dimensions: {Region: "us-east-1"})
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "Region", dimensions.first[:name]
    assert_equal "us-east-1", dimensions.first[:value]
  end

  def test_custom_dimensions_with_no_metric_dimensions
    @config.dimensions = {ServiceName: "myservice-api"}
    @reporter.report(metric: :test_metric, value: 42)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "ServiceName", dimensions.first[:name]
    assert_equal "myservice-api", dimensions.first[:value]
  end

  def test_lazy_startup_on_first_report
    refute @reporter.started?

    @reporter.report(metric: :test_metric, value: 42)

    assert @reporter.started?
  end

  def test_lazy_startup_restarts_after_stop
    @reporter.report(metric: :metric1, value: 1)
    assert @reporter.started?

    @reporter.stop!
    refute @reporter.started?

    @reporter.report(metric: :metric2, value: 2)
    assert @reporter.started?
  end

  def test_does_not_start_in_disabled_environment
    @config.enabled_environments = ["production"]
    @config.environment = "development"

    @reporter.start!

    refute @reporter.started?
  end

  def test_starts_in_enabled_environment
    @config.enabled_environments = ["production", "staging"]
    @config.environment = "staging"

    @reporter.start!

    assert @reporter.started?
  end

  def test_does_not_start_on_report_in_disabled_environment
    @config.enabled_environments = ["production"]
    @config.environment = "test"

    @reporter.report(metric: :test_metric, value: 42)

    refute @reporter.started?
    assert_equal 0, @test_client.metric_count
  end

  def test_starts_on_report_in_enabled_environment
    @config.enabled_environments = ["development", "test"]
    @config.environment = "test"

    @reporter.report(metric: :test_metric, value: 42)

    assert @reporter.started?
  end

  def test_queue_respects_max_size
    @config.queue_max_size = 5

    6.times { |i| @reporter.report(metric: :test_metric, value: i) }
    @reporter.start!
    @reporter.flush_now!

    # Metrics get aggregated, so we get 1 metric with statistic_values
    metrics = @test_client.find_metrics(metric_name: :test_metric)
    assert_equal 1, metrics.size

    # Verify the aggregated metric has 5 samples (6th was dropped)
    metric = metrics.first
    assert metric[:statistic_values], "Expected metric to be aggregated"
    assert_equal 5.0, metric[:statistic_values][:sample_count]
  end

  def test_queue_drops_oldest_metrics_on_overflow
    @config.queue_max_size = 3

    @reporter.report(metric: :test_metric, value: 1)
    @reporter.report(metric: :test_metric, value: 2)
    @reporter.report(metric: :test_metric, value: 3)
    @reporter.report(metric: :test_metric, value: 4)
    @reporter.start!
    @reporter.flush_now!

    # Metrics get aggregated into a single metric with statistic_values
    metrics = @test_client.find_metrics(metric_name: :test_metric)
    assert_equal 1, metrics.size

    # Verify oldest metric was dropped and newest were kept
    # After aggregation, we get statistic_values with 3 samples (min=2, max=4)
    metric = metrics.first
    assert metric[:statistic_values], "Expected metric to be aggregated"
    assert_equal 3.0, metric[:statistic_values][:sample_count]
    assert_equal 2.0, metric[:statistic_values][:minimum]
    assert_equal 4.0, metric[:statistic_values][:maximum]
  end

  def test_overflow_logging_is_throttled
    @config.queue_max_size = 2
    log_output = StringIO.new
    @config.logger = Logger.new(log_output)

    5.times { |i| @reporter.report(metric: :test_metric, value: i) }

    @reporter.send(:log_overflow_if_needed)

    log_content = log_output.string
    assert_match(/dropped 3 oldest metric/, log_content)
    assert_match(/max queue size: 2/, log_content)
  end

  def test_overflow_counter_resets_after_logging
    @config.queue_max_size = 2
    @config.logger = Logger.new(nil)

    5.times { |i| @reporter.report(metric: :test_metric, value: i) }
    @reporter.send(:log_overflow_if_needed)

    log_output = StringIO.new
    @config.logger = Logger.new(log_output)

    @reporter.send(:log_overflow_if_needed)

    assert_empty log_output.string
  end
end
