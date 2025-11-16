# frozen_string_literal: true

require "test_helper"
require "active_job"
require "speedshop/cloudwatch/active_job"

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

    reporter = Speedshop::Cloudwatch.reporter
    initial_count = @test_client.metric_count

    job.perform_now
    reporter.start!
    reporter.flush_now!

    assert_equal initial_count + 1, @test_client.metric_count
    metrics = @test_client.find_metrics(metric_name: :QueueLatency)
    assert_equal 1, metrics.size
    reported = metrics.first
    assert_equal "QueueLatency", reported[:metric_name]
    assert_operator reported[:value], :>=, 2.5
    # Only QueueName is reported to reduce cardinality
    assert_equal 1, reported[:dimensions].size
    assert_equal "default", reported[:dimensions].find { |d| d[:name] == "QueueName" }[:value]
  end

  def test_does_not_report_when_enqueued_at_is_nil
    job = TestJob.new("test_arg")
    job.enqueued_at = nil

    reporter = Speedshop::Cloudwatch.reporter
    initial_count = @test_client.metric_count

    job.perform_now
    reporter.start!
    reporter.flush_now!

    assert_equal initial_count, @test_client.metric_count
  end

  def test_job_executes_successfully_even_if_reporting_fails
    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    Time.stub :now, -> { raise "boom" } do
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

    reporter = Speedshop::Cloudwatch.reporter
    job.perform_now
    reporter.start!
    reporter.flush_now!

    metrics = @test_client.metrics_for_namespace("MyApp/Jobs")
    assert_equal 1, metrics.size
    reported = metrics.first
    assert_equal "QueueLatency", reported[:metric_name]
  end

  def test_respects_active_job_metrics_whitelist
    Speedshop::Cloudwatch.configure do |config|
      config.metrics[:active_job] = []
    end

    job = TestJob.new("test_arg")
    job.enqueued_at = Time.now.to_f - 1.0

    reporter = Speedshop::Cloudwatch.reporter
    initial_count = @test_client.metric_count

    job.perform_now
    reporter.start!
    reporter.flush_now!

    assert_equal initial_count, @test_client.metric_count
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
