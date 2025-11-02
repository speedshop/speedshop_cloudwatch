# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < SpeedshopCloudwatchTest
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

    metrics = run_puma_collector_with_stats(stub_puma_stats)

    metric_names = metrics.map { |m| m[:metric_name] }
    refute_includes metric_names, "Workers"
    refute_includes metric_names, "BootedWorkers"
    refute_includes metric_names, "OldWorkers"
    assert_includes metric_names, "Running"
    assert_includes metric_names, "Backlog"
    assert_includes metric_names, "PoolCapacity"
    assert_includes metric_names, "MaxThreads"
  end

  def test_collects_metrics_with_clustered_mode_stats
    metrics = collect_clustered_puma_metrics

    assert_collects_cluster_level_metrics(metrics)
    assert_collects_worker_level_metrics(metrics)
    assert_collects_metrics_for_all_workers(metrics)
  end

  private

  def run_puma_collector_with_stats(stats)
    ::Puma.stub(:stats_hash, stats) do
      collector = Speedshop::Cloudwatch::Puma::Collector.new
      collector.collect
    end
    Speedshop::Cloudwatch.reporter.queue.dup
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

  def assert_collects_cluster_level_metrics(metrics)
    metric_names = metrics.map { |m| m[:metric_name] }
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "BootedWorkers"
    assert_includes metric_names, "OldWorkers"
  end

  def assert_collects_worker_level_metrics(metrics)
    metric_names = metrics.map { |m| m[:metric_name] }
    ["Running", "Backlog", "PoolCapacity", "MaxThreads"].each do |metric|
      assert_includes metric_names, metric
    end

    running_metrics = metrics.select { |m| m[:metric_name] == "Running" && m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" } }
    assert_equal 2, running_metrics.size
  end

  def assert_collects_metrics_for_all_workers(metrics)
    [0, 1].each do |worker_index|
      worker_metrics = metrics.select do |m|
        m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" && d[:value] == worker_index.to_s }
      end
      assert_operator worker_metrics.size, :>, 0
    end
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.namespaces[:puma] = "MyApp/Puma"
    end

    stub_puma_stats = {workers: 1, booted_workers: 1, old_workers: 0, running: 5, backlog: 0, pool_capacity: 5, max_threads: 5}
    metrics = run_puma_collector_with_stats(stub_puma_stats)

    assert metrics.all? { |m| m[:namespace] == "MyApp/Puma" }, "Expected all metrics to use 'MyApp/Puma' namespace"
  end

  def test_logs_error_when_collection_fails
    logger = TestDoubles::LoggerDouble.new

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    run_puma_collector_with_stats(-> { raise "boom" })

    assert logger.error_logged?("Failed to collect Puma metrics"), "Expected error to be logged"
  end
end
