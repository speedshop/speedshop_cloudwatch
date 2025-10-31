# frozen_string_literal: true

require "test_helper"

class CloudwatchTest < Minitest::Test
  def test_configure_yields_configuration
    yielded_config = nil
    result = Speedshop::Cloudwatch.configure do |config|
      yielded_config = config
    end

    assert_kind_of Speedshop::Cloudwatch::Configuration, yielded_config
    assert_kind_of Speedshop::Cloudwatch::Configuration, result
  end

  def test_configure_allows_setting_options
    config = Speedshop::Cloudwatch.configure do |c|
      c.interval = 120
      c.enabled[:puma] = false
    end

    assert_equal 120, config.interval
    refute config.enabled[:puma]
  end

  def test_config_returns_configuration_instance
    config = Speedshop::Cloudwatch.config
    assert_kind_of Speedshop::Cloudwatch::Configuration, config
  end

  def test_reporter_returns_metric_reporter_instance
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.logger = Logger.new(nil)
    end

    reporter = Speedshop::Cloudwatch.reporter
    assert_kind_of Speedshop::Cloudwatch::MetricReporter, reporter
  end

  def test_reporter_mutex_created_at_require_time
    mutex = Speedshop::Cloudwatch.instance_variable_get(:@reporter_mutex)
    assert_kind_of Mutex, mutex
  end
end
