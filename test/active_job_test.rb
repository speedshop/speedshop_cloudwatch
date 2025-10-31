# frozen_string_literal: true

require "test_helper"

begin
  require "active_job"
rescue LoadError
  return
end

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

class TestJob < ActiveJob::Base
  include Speedshop::Cloudwatch::ActiveJob

  queue_as :default

  def perform(arg)
    arg
  end
end

class ActiveJobTest < Minitest::Test
  def setup
    @client = Minitest::Mock.new
    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.logger = Logger.new(nil)
    end
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end

  def test_active_job_module_is_defined
    assert defined?(Speedshop::Cloudwatch::ActiveJob)
  end

  def test_active_job_has_included_method
    assert_respond_to Speedshop::Cloudwatch::ActiveJob, :included
  end

  def test_reports_queue_time_when_job_executes
    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 2.5

    reported_metric = nil
    reported_value = nil
    reported_namespace = nil
    reported_dimensions = nil

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(metric, value, namespace:, unit: nil, dimensions: nil) {
      reported_metric = metric
      reported_value = value
      reported_namespace = namespace
      reported_dimensions = dimensions
    } do
      job.perform_now
    end

    assert_equal "QueueLatency", reported_metric
    assert_operator reported_value, :>=, 2.5
    assert_equal "ActiveJob", reported_namespace
    assert_equal 2, reported_dimensions.size
    assert_equal "JobClass", reported_dimensions[0][:name]
    assert_equal "TestJob", reported_dimensions[0][:value]
    assert_equal "QueueName", reported_dimensions[1][:name]
    assert_equal "default", reported_dimensions[1][:value]
  end

  def test_does_not_report_when_enqueued_at_is_nil
    job = TestJob.new("test_arg")
    job.enqueued_at = nil

    report_called = false
    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(*) { report_called = true } do
      job.perform_now
    end

    refute report_called
  end

  def test_job_executes_successfully_even_if_reporting_fails
    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(*) { raise "CloudWatch error" } do
      result = job.perform_now
      assert_equal "test_arg", result
    end
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.namespaces[:active_job] = "MyApp/Jobs"
    end

    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    reported_namespace = nil
    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(metric, value, namespace:, **kwargs) {
      reported_namespace = namespace
    } do
      job.perform_now
    end

    assert_equal "MyApp/Jobs", reported_namespace
  end

  def test_respects_active_job_enabled_flag
    Speedshop::Cloudwatch.configure do |config|
      config.enabled[:active_job] = false
    end

    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    reporter = Speedshop::Cloudwatch.reporter
    queue = reporter.queue
    initial_size = queue.size

    job.perform_now

    assert_equal initial_size, queue.size
  end

  def test_respects_active_job_metrics_whitelist
    Speedshop::Cloudwatch.configure do |config|
      config.metrics[:active_job] = []
    end

    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    reporter = Speedshop::Cloudwatch.reporter
    queue = reporter.queue
    initial_size = queue.size

    job.perform_now

    assert_equal initial_size, queue.size
  end
end
