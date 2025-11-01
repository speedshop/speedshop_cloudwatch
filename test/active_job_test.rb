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

class ActiveJobTest < SpeedshopCloudwatchTest
  def setup
    super
    Speedshop::Cloudwatch.config.namespaces[:active_job] = "ActiveJob"
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
    reported_integration = nil
    reported_dimensions = nil

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(metric, value, integration:, unit: nil, dimensions: nil) {
      reported_metric = metric
      reported_value = value
      reported_integration = integration
      reported_dimensions = dimensions
    } do
      job.perform_now
    end

    assert_equal "QueueLatency", reported_metric
    assert_operator reported_value, :>=, 2.5
    assert_equal :active_job, reported_integration
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

    reported_integration = nil
    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(metric, value, integration:, **kwargs) {
      reported_integration = integration
    } do
      job.perform_now
    end

    assert_equal :active_job, reported_integration
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

  def test_logs_error_when_collection_fails
    error_logged = false
    logger = Object.new
    logger.define_singleton_method(:error) { |msg| error_logged = true if msg.include?("Failed to collect ActiveJob metrics") }
    logger.define_singleton_method(:debug) { |msg| }
    logger.define_singleton_method(:info) { |msg| }

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    job = TestJob.new("test_arg")
    job.stub :enqueued_at, -> { raise "boom" } do
      result = job.perform_now
      assert_equal "test_arg", result
    end

    assert error_logged, "Expected error to be logged"
  end
end
