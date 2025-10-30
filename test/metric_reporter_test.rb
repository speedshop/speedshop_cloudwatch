# frozen_string_literal: true

require "test_helper"

class MetricReporterTest < Minitest::Test
  def setup
    @client = Minitest::Mock.new
    @config = Speedshop::Cloudwatch::Configuration.new
    @config.interval = 60
    @config.client = @client
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
end
