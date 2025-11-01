# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < SpeedshopCloudwatchTest
  def test_puma_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Puma)
  end

  def test_collects_metrics_with_single_mode_stats
    stub_puma_stats = {
      workers: 0,
      booted_workers: 0,
      old_workers: 0,
      running: 5,
      backlog: 0,
      pool_capacity: 5,
      max_threads: 5
    }

    reporter = run_puma_collector_with_stats(stub_puma_stats)

    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    refute_includes metric_names, "Workers"
    refute_includes metric_names, "BootedWorkers"
    refute_includes metric_names, "OldWorkers"
    assert_includes metric_names, "Running"
    assert_includes metric_names, "Backlog"
    assert_includes metric_names, "PoolCapacity"
    assert_includes metric_names, "MaxThreads"
  end

  def test_collects_metrics_with_clustered_mode_stats
    reporter = collect_clustered_puma_metrics

    assert_collects_cluster_level_metrics(reporter)
    assert_collects_worker_level_metrics(reporter)
    assert_collects_metrics_for_all_workers(reporter)
  end

  private

  def run_puma_collector_with_stats(stats, reporter: TestDoubles::ReporterDouble.new)
    ::Puma.stub(:stats_hash, stats) do
      Speedshop::Cloudwatch::Puma.register(namespace: "Puma", reporter: reporter)
      collector = reporter.collectors.last
      collector[:block].call
    end
    reporter
  end

  def collect_clustered_puma_metrics
    run_puma_collector_with_stats(clustered_puma_stats)
  end

  def clustered_puma_stats
    {
      workers: 2,
      booted_workers: 2,
      old_workers: 0,
      worker_status: [
        {last_status: {running: 5, backlog: 0, pool_capacity: 5, max_threads: 5}},
        {last_status: {running: 4, backlog: 1, pool_capacity: 5, max_threads: 5}}
      ]
    }
  end

  def assert_collects_cluster_level_metrics(reporter)
    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "BootedWorkers"
    assert_includes metric_names, "OldWorkers"
  end

  def assert_collects_worker_level_metrics(reporter)
    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    ["Running", "Backlog", "PoolCapacity", "MaxThreads"].each do |metric|
      assert_includes metric_names, metric
    end

    running_metrics = reporter.metrics_collected.select { |m| m[:name] == "Running" }
    assert_equal 2, running_metrics.size
  end

  def assert_collects_metrics_for_all_workers(reporter)
    [0, 1].each do |worker_index|
      worker_metrics = reporter.metrics_collected.select do |m|
        m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" && d[:value] == worker_index.to_s }
      end
      assert_operator worker_metrics.size, :>, 0
    end
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
      config.namespaces[:puma] = "MyApp/Puma"
    end

    stub_puma_stats = {workers: 1, booted_workers: 1, old_workers: 0, running: 5, backlog: 0, pool_capacity: 5, max_threads: 5}
    reporter = run_puma_collector_with_stats(stub_puma_stats)

    assert reporter.metrics_collected.all? { |m| m[:namespace] == "MyApp/Puma" }, "Expected all metrics to use 'MyApp/Puma' namespace"
  end

  def test_logs_error_when_collection_fails
    error_logged = false
    logger = Object.new
    logger.define_singleton_method(:error) { |msg| error_logged = true if msg.include?("Failed to collect Puma metrics") }
    logger.define_singleton_method(:debug) { |msg| }
    logger.define_singleton_method(:info) { |msg| }

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    run_puma_collector_with_stats(-> { raise "boom" })

    assert error_logged, "Expected error to be logged"
  end
end
