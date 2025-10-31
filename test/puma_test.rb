# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < Minitest::Test
  def test_puma_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Puma)
  end

  def test_collects_metrics_with_single_mode_stats
    reporter = TestDoubles::ReporterDouble.new

    stub_puma_stats = {
      workers: 0,
      booted_workers: 0,
      old_workers: 0,
      running: 5,
      backlog: 0,
      pool_capacity: 5,
      max_threads: 5
    }

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.register(namespace: "Puma", reporter: reporter)
      collector = reporter.collectors.last
      collector.call
    end

    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "BootedWorkers"
    assert_includes metric_names, "OldWorkers"
    assert_includes metric_names, "Running"
    assert_includes metric_names, "Backlog"
    assert_includes metric_names, "PoolCapacity"
    assert_includes metric_names, "MaxThreads"
  end

  def test_collects_metrics_with_clustered_mode_stats
    reporter = TestDoubles::ReporterDouble.new

    stub_puma_stats = {
      workers: 2,
      booted_workers: 2,
      old_workers: 0,
      worker_status: [
        {
          last_status: {
            running: 5,
            backlog: 0,
            pool_capacity: 5,
            max_threads: 5
          }
        },
        {
          last_status: {
            running: 4,
            backlog: 1,
            pool_capacity: 5,
            max_threads: 5
          }
        }
      ]
    }

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.register(namespace: "Puma", reporter: reporter)
      collector = reporter.collectors.last
      collector.call
    end

    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "BootedWorkers"
    assert_includes metric_names, "OldWorkers"
    assert_includes metric_names, "Running"
    assert_includes metric_names, "Backlog"
    assert_includes metric_names, "PoolCapacity"
    assert_includes metric_names, "MaxThreads"

    running_metrics = reporter.metrics_collected.select { |m| m[:name] == "Running" }
    assert_equal 2, running_metrics.size

    worker_0_metrics = reporter.metrics_collected.select do |m|
      m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" && d[:value] == "0" }
    end
    assert_operator worker_0_metrics.size, :>, 0

    worker_1_metrics = reporter.metrics_collected.select do |m|
      m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" && d[:value] == "1" }
    end
    assert_operator worker_1_metrics.size, :>, 0
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
      config.namespaces[:puma] = "MyApp/Puma"
    end

    reporter = TestDoubles::ReporterDouble.new

    stub_puma_stats = {workers: 1, booted_workers: 1, old_workers: 0, running: 5, backlog: 0, pool_capacity: 5, max_threads: 5}

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.register(reporter: reporter)
      collector = reporter.collectors.last
      collector.call
    end

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

    reporter = TestDoubles::ReporterDouble.new

    ::Puma.stub(:stats_hash, -> { raise "boom" }) do
      Speedshop::Cloudwatch::Puma.register(namespace: "Puma", reporter: reporter)
      collector = reporter.collectors.last
      collector.call
    end

    assert error_logged, "Expected error to be logged"
  end
end
