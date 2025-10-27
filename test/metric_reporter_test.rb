# frozen_string_literal: true

require "test_helper"

class MetricReporterTest < Minitest::Test
  def setup
    @client = Minitest::Mock.new
    @reporter = Speedshop::Cloudwatch::MetricReporter.new(
      namespace: "TestApp",
      interval: 60,
      client: @client
    )
  end

  def teardown
    @reporter&.stop!
  end

  def test_can_initialize_reporter
    assert_equal "TestApp", @reporter.namespace
    assert_equal 60, @reporter.interval
  end

  def test_queues_metrics
    @reporter.report("test_metric", 42)
    @reporter.report("another_metric", 100, unit: "Count")
  end

  def test_can_start_and_stop
    @reporter.start!
    @reporter.stop!
  end
end
