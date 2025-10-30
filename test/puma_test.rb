# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < Minitest::Test
  def test_puma_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Puma)
  end

  def test_collects_metrics_with_single_mode_stats
    client = Minitest::Mock.new
    metrics_collected = []

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    reporter.define_singleton_method(:report) do |metric_name, value, **options|
      metrics_collected << {name: metric_name, value: value, **options}
    end

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
      collector = reporter.instance_variable_get(:@collectors).last
      collector.call
    end

    metric_names = metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "workers"
    assert_includes metric_names, "booted_workers"
    assert_includes metric_names, "old_workers"
    assert_includes metric_names, "running"
    assert_includes metric_names, "backlog"
    assert_includes metric_names, "pool_capacity"
    assert_includes metric_names, "max_threads"
  end

  def test_collects_metrics_with_clustered_mode_stats
    client = Minitest::Mock.new
    metrics_collected = []

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    reporter.define_singleton_method(:report) do |metric_name, value, **options|
      metrics_collected << {name: metric_name, value: value, **options}
    end

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
      collector = reporter.instance_variable_get(:@collectors).last
      collector.call
    end

    metric_names = metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "workers"
    assert_includes metric_names, "booted_workers"
    assert_includes metric_names, "old_workers"
    assert_includes metric_names, "running"
    assert_includes metric_names, "backlog"
    assert_includes metric_names, "pool_capacity"
    assert_includes metric_names, "max_threads"

    running_metrics = metrics_collected.select { |m| m[:name] == "running" }
    assert_equal 2, running_metrics.size

    worker_0_metrics = metrics_collected.select do |m|
      m[:dimensions]&.any? { |d| d[:name] == "WorkerIndex" && d[:value] == "0" }
    end
    assert_operator worker_0_metrics.size, :>, 0

    worker_1_metrics = metrics_collected.select do |m|
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

    metrics_collected = []
    reporter = Speedshop::Cloudwatch.reporter
    reporter.define_singleton_method(:report) do |metric_name, value, **options|
      metrics_collected << {name: metric_name, value: value, **options}
    end

    stub_puma_stats = {workers: 1, booted_workers: 1, old_workers: 0, running: 5, backlog: 0, pool_capacity: 5, max_threads: 5}

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.register(reporter: reporter)
      collector = reporter.instance_variable_get(:@collectors).last
      collector.call
    end

    assert metrics_collected.all? { |m| m[:namespace] == "MyApp/Puma" }, "Expected all metrics to use 'MyApp/Puma' namespace"
  end
end
