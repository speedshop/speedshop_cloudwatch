# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/api"
require "connection_pool"

class SidekiqTest < Minitest::Test
  def setup
    Sidekiq.configure_client do |config|
      config.redis = {url: "redis://localhost:6379/15"}
    end
    Sidekiq.configure_server do |config|
      config.redis = {url: "redis://localhost:6379/15"}
    end
    Sidekiq.redis(&:flushdb)

    @lifecycle_callbacks = {}
    callbacks = @lifecycle_callbacks
    @sidekiq_config_mock = Object.new
    @sidekiq_config_mock.define_singleton_method(:on) do |event, &block|
      callbacks[event] = block
    end
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
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    assert_equal 1, reporter.instance_variable_get(:@collectors).size
  end

  def test_lifecycle_hooks_registered_for_oss
    client = Minitest::Mock.new
    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    assert @lifecycle_callbacks.key?(:startup), "Expected :startup hook to be registered"
    assert @lifecycle_callbacks.key?(:quiet), "Expected :quiet hook to be registered"
    assert @lifecycle_callbacks.key?(:shutdown), "Expected :shutdown hook to be registered"
    refute @lifecycle_callbacks.key?(:leader), "Expected :leader hook NOT to be registered for OSS"
  end

  def test_lifecycle_hooks_registered_for_enterprise
    client = Minitest::Mock.new
    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
      end
    )

    enterprise_module = Module.new
    ::Sidekiq.const_set(:Enterprise, enterprise_module)

    begin
      ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
        Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
      end

      assert @lifecycle_callbacks.key?(:leader), "Expected :leader hook to be registered for Enterprise"
      assert @lifecycle_callbacks.key?(:quiet), "Expected :quiet hook to be registered"
      assert @lifecycle_callbacks.key?(:shutdown), "Expected :shutdown hook to be registered"
      refute @lifecycle_callbacks.key?(:startup), "Expected :startup hook NOT to be registered for Enterprise"
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
      end
    )

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter)
    end

    @lifecycle_callbacks[:startup].call
    assert reporter.instance_variable_get(:@running), "Reporter should be running after startup"

    @lifecycle_callbacks[:quiet].call
    refute reporter.instance_variable_get(:@running), "Reporter should be stopped after quiet"
  end

  def test_collects_all_metrics_with_real_sidekiq_data
    client = Minitest::Mock.new
    metrics_collected = []

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
      end
    )

    reporter.define_singleton_method(:report) do |metric_name, value, **options|
      metrics_collected << {name: metric_name, value: value, **options}
    end

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter, process_metrics: true)

      collector = reporter.instance_variable_get(:@collectors).last
      collector.call
    end

    metric_names = metrics_collected.map { |m| m[:name] }
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
    client = Minitest::Mock.new
    metrics_collected = []

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
      end
    )

    reporter.define_singleton_method(:report) do |metric_name, value, **options|
      metrics_collected << {name: metric_name, value: value, **options}
    end

    ::Sidekiq.stub(:configure_server, proc { |&block| block.call(@sidekiq_config_mock) }) do
      Speedshop::Cloudwatch::Sidekiq.register(namespace: "Sidekiq", reporter: reporter, process_metrics: false)

      collector = reporter.instance_variable_get(:@collectors).last
      collector.call
    end

    process_utilization_metrics = metrics_collected.select do |m|
      m[:name] == "Utilization" && m[:dimensions]&.any? { |d| d[:name] == "Hostname" }
    end
    assert_equal 0, process_utilization_metrics.size
  end
end
