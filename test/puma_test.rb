# frozen_string_literal: true

require "test_helper"
require "puma"
require "speedshop/cloudwatch/puma"

class PumaTest < SpeedshopCloudwatchTest
  def test_collects_metrics_with_single_mode_stats
    Speedshop::Cloudwatch.configure do |config|
      config.metrics[:puma] = [:Running, :Backlog, :PoolCapacity, :MaxThreads]
    end

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
    Speedshop::Cloudwatch.configure do |config|
      config.metrics[:puma] = [
        :Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads
      ]
    end

    metrics = collect_clustered_puma_metrics

    assert_collects_cluster_level_metrics(metrics)
    assert_collects_aggregate_worker_metrics(metrics)
  end

  private

  def run_puma_collector_with_stats(stats)
    ::Puma.stub(:stats_hash, stats) do
      collector = Speedshop::Cloudwatch::Puma.new
      collector.collect
    end
    reporter = Speedshop::Cloudwatch.reporter
    reporter.start!
    reporter.flush_now!
    @test_client.find_metrics
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

  def assert_collects_aggregate_worker_metrics(metrics)
    metric_names = metrics.map { |m| m[:metric_name] }
    ["Running", "Backlog", "PoolCapacity", "MaxThreads"].each do |metric|
      assert_includes metric_names, metric
    end

    # Verify that worker metrics are reported without WorkerIndex dimension
    running_metrics = metrics.select { |m| m[:metric_name] == "Running" && m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" } }
    assert_equal 0, running_metrics.size, "Expected no Running metrics with WorkerIndex dimension"

    # Verify aggregate metrics exist (without dimensions or with only integration dimension)
    aggregate_running = metrics.select do |m|
      m[:metric_name] == "Running" &&
        (m[:dimensions].nil? || m[:dimensions].empty? || m[:dimensions].none? { |d| d[:name] == "WorkerIndex" })
    end
    assert_operator aggregate_running.size, :>, 0, "Expected at least one aggregate Running metric"
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.namespaces[:puma] = "MyApp/Puma"
      config.metrics[:puma] = [:Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads]
    end

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

  private

  def stub_puma_stats
    {
      workers: 0,
      booted_workers: 0,
      old_workers: 0,
      running: 5,
      backlog: 0,
      pool_capacity: 5,
      max_threads: 5
    }
  end
end
