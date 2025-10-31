# frozen_string_literal: true

require "test_helper"

class MetricReporterTest < Minitest::Test
  def setup
    @client = Minitest::Mock.new
    @config = Speedshop::Cloudwatch::Configuration.new
    @config.interval = 60
    @config.client = @client
    @config.logger = Logger.new(nil)
    @reporter = Speedshop::Cloudwatch::MetricReporter.new(config: @config)
  end

  def teardown
    @reporter&.stop!
  end

  def test_queues_metrics
    @reporter.report("test_metric", 42, namespace: "TestApp")
    @reporter.report("another_metric", 100, namespace: "TestApp", unit: "Count")
  end

  def test_can_start_and_stop
    @reporter.start!
    @reporter.stop!
  end

  def test_respects_puma_enabled_flag
    @config.enabled[:puma] = false
    @reporter.report("workers", 4, namespace: "Puma")

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_puma_metrics_whitelist
    @config.metrics[:puma] = [:workers]
    @reporter.report("workers", 4, namespace: "Puma")
    @reporter.report("booted_workers", 4, namespace: "Puma")

    queue = @reporter.queue
    assert_equal 1, queue.size
    assert_equal "workers", queue.first[:metric_name]
  end

  def test_respects_sidekiq_enabled_flag
    @config.enabled[:sidekiq] = false
    @reporter.report("EnqueuedJobs", 10, namespace: "Sidekiq")

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_sidekiq_metrics_whitelist
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency]
    @reporter.report("EnqueuedJobs", 10, namespace: "Sidekiq")
    @reporter.report("ProcessedJobs", 100, namespace: "Sidekiq")
    @reporter.report("QueueLatency", 5.2, namespace: "Sidekiq")

    queue = @reporter.queue
    assert_equal 2, queue.size
    metric_names = queue.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "QueueLatency"
    refute_includes metric_names, "ProcessedJobs"
  end

  def test_respects_rack_enabled_flag
    @config.enabled[:rack] = false
    @reporter.report("request_queue_time", 50, namespace: "Rack")

    queue = @reporter.queue
    assert_empty queue
  end

  def test_respects_active_job_enabled_flag
    @config.enabled[:active_job] = false
    @reporter.report("job_queue_time", 2.5, namespace: "ActiveJob")

    queue = @reporter.queue
    assert_empty queue
  end

  def test_allows_unknown_namespaces
    @reporter.report("custom_metric", 42, namespace: "CustomNamespace")

    queue = @reporter.queue
    assert_equal 1, queue.size
  end

  def test_does_not_start_when_no_integrations_enabled
    @config.enabled[:puma] = false
    @config.enabled[:sidekiq] = false
    @config.enabled[:rack] = false
    @config.enabled[:active_job] = false

    @reporter.start!

    assert_nil @reporter.thread
    refute @reporter.running
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
    thread1 = @reporter.thread

    @reporter.start!
    thread2 = @reporter.thread

    assert_same thread1, thread2
  end

  def test_started_detects_pid_change
    @reporter.start!
    original_pid = @reporter.instance_variable_get(:@pid)

    @reporter.instance_variable_set(:@pid, original_pid + 1)

    refute @reporter.started?
  end

  def test_started_detects_dead_thread
    @reporter.start!
    @reporter.instance_variable_get(:@thread).kill
    @reporter.instance_variable_get(:@thread).join

    refute @reporter.started?
  end
end
