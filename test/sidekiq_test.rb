# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/api"
require "connection_pool"

class SidekiqTest < SpeedshopCloudwatchTest
  def setup
    super
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
    super
  end

  def test_sidekiq_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Sidekiq)
  end

  def test_can_register_collector
    reporter = create_test_reporter

    stub_sidekiq_configure_server do
      Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter)
      @sidekiq_config_mock.callbacks[:startup].call
    end

    assert_equal 1, reporter.collectors.size
  end

  def test_lifecycle_hooks_registered_for_oss
    reporter = create_test_reporter

    stub_sidekiq_configure_server do
      Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter)
    end

    assert @sidekiq_config_mock.callbacks.key?(:startup), "Expected :startup hook to be registered"
    assert @sidekiq_config_mock.callbacks.key?(:quiet), "Expected :quiet hook to be registered"
    assert @sidekiq_config_mock.callbacks.key?(:shutdown), "Expected :shutdown hook to be registered"
    refute @sidekiq_config_mock.callbacks.key?(:leader), "Expected :leader hook NOT to be registered for OSS"
  end

  def test_filters_queues_when_configured
    configure_sidekiq(sidekiq_queues: ["critical", "default"])
    queue_names = collect_sidekiq_queue_names

    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    refute_includes queue_names, "low_priority"
  end

  def test_monitors_all_queues_by_default
    configure_sidekiq(sidekiq_queues: nil)
    queue_names = collect_sidekiq_queue_names

    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    assert_includes queue_names, "low_priority"
  end

  private

  def create_test_reporter
    client = Minitest::Mock.new
    Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
        c.logger = Logger.new(nil)
      end
    )
  end

  def stub_sidekiq_configure_server(&block)
    ::Sidekiq.stub(:configure_server, proc { |&blk| blk.call(@sidekiq_config_mock) }, &block)
  end

  def configure_cloudwatch_for_test
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
    end
  end

  def sample_queues
    [
      TestDoubles::QueueDouble.new("critical", 1, 1.5),
      TestDoubles::QueueDouble.new("default", 2, 0.5),
      TestDoubles::QueueDouble.new("low_priority", 3, 2.0)
    ]
  end

  def configure_sidekiq(sidekiq_queues:)
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.interval = 60
      config.logger = Logger.new(nil)
      config.sidekiq_queues = sidekiq_queues
    end
  end

  def collect_sidekiq_queue_names
    test_reporter = TestDoubles::ReporterDouble.new
    ::Sidekiq::Queue.stub(:all, sample_queues) do
      stub_sidekiq_configure_server do
        Speedshop::Cloudwatch::Sidekiq.register(reporter: test_reporter)
        @sidekiq_config_mock.callbacks[:startup].call
        test_reporter.collectors.last[:block].call
      end
    end

    queue_metrics = test_reporter.metrics_collected.select { |m| m[:dimensions]&.any? { |d| d[:name] == "QueueName" } }
    queue_metrics.map { |m| m[:dimensions].find { |d| d[:name] == "QueueName" }[:value] }.uniq
  end

  def test_lifecycle_hooks_registered_for_enterprise
    reporter = create_test_reporter

    enterprise_module = Module.new
    ::Sidekiq.const_set(:Enterprise, enterprise_module)

    begin
      stub_sidekiq_configure_server do
        Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter)
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
    configure_cloudwatch_for_test
    reporter = Speedshop::Cloudwatch.reporter

    stub_sidekiq_configure_server do
      Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter)
    end

    assert_equal 0, reporter.collectors.size, "Sidekiq should not be registered yet"
    @sidekiq_config_mock.callbacks[:startup].call
    assert_equal 1, reporter.collectors.size, "Sidekiq should be registered after startup"

    @sidekiq_config_mock.callbacks[:quiet].call
    assert_equal 0, reporter.collectors.size, "Sidekiq should be unregistered after quiet"
    refute reporter.running, "Reporter should be stopped after quiet"
  end

  def test_collects_all_metrics_with_real_sidekiq_data
    configure_cloudwatch_for_test
    reporter = TestDoubles::ReporterDouble.new

    stub_sidekiq_configure_server do
      Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter, process_metrics: true)
      @sidekiq_config_mock.callbacks[:startup].call

      collector = reporter.collectors.last
      collector[:block].call
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
    configure_cloudwatch_for_test
    reporter = TestDoubles::ReporterDouble.new

    stub_sidekiq_configure_server do
      Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter, process_metrics: false)
      @sidekiq_config_mock.callbacks[:startup].call

      collector = reporter.collectors.last
      collector[:block].call
    end

    process_utilization_metrics = reporter.metrics_collected.select do |m|
      m[:name] == "Utilization" && m[:dimensions]&.any? { |d| d[:name] == "Hostname" }
    end
    assert_equal 0, process_utilization_metrics.size
  end

  def test_logs_error_when_collection_fails
    error_logged = false
    logger = Object.new
    logger.define_singleton_method(:error) { |msg| error_logged = true if msg.include?("Failed to collect Sidekiq metrics") }
    logger.define_singleton_method(:debug) { |msg| }
    logger.define_singleton_method(:info) { |msg| }

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    reporter = TestDoubles::ReporterDouble.new

    ::Sidekiq::Stats.stub(:new, -> { raise "boom" }) do
      stub_sidekiq_configure_server do
        Speedshop::Cloudwatch::Sidekiq.register(reporter: reporter)
        @sidekiq_config_mock.callbacks[:startup].call
        collector = reporter.collectors.last
        collector[:block].call
      end
    end

    assert error_logged, "Expected error to be logged"
  end
end
