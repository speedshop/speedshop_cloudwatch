# frozen_string_literal: true

require "test_helper"
require "active_job"

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
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end

  def test_reports_queue_time_when_job_executes
    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 2.5

    reported_kwargs = nil

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(**kwargs) {
      reported_kwargs = kwargs
    } do
      job.perform_now
    end

    assert_equal :QueueLatency, reported_kwargs[:metric]
    assert_operator reported_kwargs[:value], :>=, 2.5
    assert_equal 2, reported_kwargs[:dimensions].size
    assert_equal "TestJob", reported_kwargs[:dimensions][:JobClass]
    assert_equal "default", reported_kwargs[:dimensions][:QueueName]
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

    reported_kwargs = nil
    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(**kwargs) {
      reported_kwargs = kwargs
    } do
      job.perform_now
    end

    assert_equal :QueueLatency, reported_kwargs[:metric]
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
    logger = TestDoubles::LoggerDouble.new

    Speedshop::Cloudwatch.configure do |config|
      config.logger = logger
    end

    job = TestJob.new("test_arg")
    job.stub :enqueued_at, -> { raise "boom" } do
      result = job.perform_now
      assert_equal "test_arg", result
    end

    assert logger.error_logged?("Failed to collect ActiveJob metrics"), "Expected error to be logged"
  end
end
