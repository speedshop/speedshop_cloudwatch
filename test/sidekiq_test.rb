# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/api"
require "connection_pool"

class SidekiqTest < Minitest::Test
  def setup
    Sidekiq.configure_client do |config|
      config.redis = {url: "redis://localhost:6379/15"}
      config.logger = Logger.new(nil)
    end
    Sidekiq.configure_server do |config|
      config.redis = {url: "redis://localhost:6379/15"}
      config.logger = Logger.new(nil)
    end
    Sidekiq.redis(&:flushdb)

    @sidekiq_config_mock = TestDoubles::SidekiqConfigDouble.new
  end

  def teardown
    Sidekiq.redis(&:flushdb)
  end

  def test_sidekiq_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Sidekiq)
  end

  def test_can_register_collector
    client = Minitest::Mock.new
    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    assert_equal 1, reporter.collectors.size
  end

  def test_lifecycle_hooks_registered_for_oss
    client = Minitest::Mock.new
    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    assert @sidekiq_config_mock.callbacks.key?(:startup), "Expected :startup hook to be registered"
    assert @sidekiq_config_mock.callbacks.key?(:quiet), "Expected :quiet hook to be registered"
    assert @sidekiq_config_mock.callbacks.key?(:shutdown), "Expected :shutdown hook to be registered"
    refute @sidekiq_config_mock.callbacks.key?(:leader), "Expected :leader hook NOT to be registered for OSS"
  end

  def test_filters_queues_when_configured
    queues = [
      TestDoubles::QueueDouble.new("critical", 1, 1.5),
      TestDoubles::QueueDouble.new("default", 2, 0.5),
      TestDoubles::QueueDouble.new("low_priority", 3, 2.0)
    ]

    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
      config.sidekiq_queues = ["critical", "default"]
    end

    test_reporter = TestDoubles::ReporterDouble.new

    ::Sidekiq::Queue.stub(:all, queues) do
      ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
        Speedshop::Cloudwatch::Sidekiq.register(reporter: test_reporter)
        collector = test_reporter.collectors.last
        collector.call
      end
    end

    queue_metrics = test_reporter.metrics_collected.select { |m| m[:dimensions]&.any? { |d| d[:name] == "QueueName" } }
    queue_names = queue_metrics.map { |m| m[:dimensions].find { |d| d[:name] == "QueueName" }[:value] }.uniq

    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    refute_includes queue_names, "low_priority"
  end

  def test_monitors_all_queues_by_default
    queues = [
      TestDoubles::QueueDouble.new("critical", 1, 1.5),
      TestDoubles::QueueDouble.new("default", 2, 0.5),
      TestDoubles::QueueDouble.new("low_priority", 3, 2.0)
    ]

    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
      config.sidekiq_queues = nil
    end

    test_reporter = TestDoubles::ReporterDouble.new

    ::Sidekiq::Queue.stub(:all, queues) do
      ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
        Speedshop::Cloudwatch::Sidekiq.register(reporter: test_reporter)
        collector = test_reporter.collectors.last
        collector.call
      end
    end

    queue_metrics = test_reporter.metrics_collected.select { |m| m[:dimensions]&.any? { |d| d[:name] == "QueueName" } }
    queue_names = queue_metrics.map { |m| m[:dimensions].find { |d| d[:name] == "QueueName" }[:value] }.uniq

    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    assert_includes queue_names, "low_priority"
  end

  def test_lifecycle_hooks_registered_for_enterprise
    client = Minitest::Mock.new
    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    enterprise_module = Module.new
    ::Sidekiq.const_set(:Enterprise, enterprise_module)

    begin
      ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
        Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
      end

      assert @sidekiq_config_mock.callbacks.key?(:leader), "Expected :leader hook to be registered for Enterprise"
      assert @sidekiq_config_mock.callbacks.key?(:quiet), "Expected :quiet hook to be registered"
      assert @sidekiq_config_mock.callbacks.key?(:shutdown), "Expected :shutdown hook to be registered"
      refute @sidekiq_config_mock.callbacks.key?(:startup), "Expected :startup hook NOT to be registered for Enterprise"
    ensure
      ::Sidekiq.send(:remove_const, :Enterprise)
    end
  end

  def test_lifecycle_hooks_call_reporter_methods
    client = Minitest::Mock.new
    client.expect(:put_metric_data, nil, [Hash])

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    @sidekiq_config_mock.callbacks[:startup].call
    assert reporter.running, "Reporter should be running after startup"

    @sidekiq_config_mock.callbacks[:quiet].call
    refute reporter.running, "Reporter should be stopped after quiet"
  end

  def test_collects_all_metrics_with_real_sidekiq_data
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
    end

    reporter = TestDoubles::ReporterDouble.new

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter, process_metrics: true)

      collector = reporter.collectors.last
      collector.call
    end

    metric_names = reporter.metrics_collected.map { |m| m[:name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "ProcessedJobs"
    assert_includes metric_names, "FailedJobs"
    assert_includes metric_names, "ScheduledJobs"
    assert_includes metric_names, "RetryJobs"
    assert_includes metric_names, "DeadJobs"
    assert_includes metric_names, "Workers"
    assert_includes metric_names, "Processes"
    assert_includes metric_names, "DefaultQueueLatency"
    assert_includes metric_names, "Capacity"
  end

  def test_process_metrics_can_be_disabled
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
    end

    reporter = TestDoubles::ReporterDouble.new

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter, process_metrics: false)

      collector = reporter.collectors.last
      collector.call
    end

    process_utilization_metrics = reporter.metrics_collected.select do |m|
      m[:name] == "Utilization" && m[:dimensions]&.any? { |d| d[:name] == "Hostname" }
    end
    assert_equal 0, process_utilization_metrics.size
  end
end
