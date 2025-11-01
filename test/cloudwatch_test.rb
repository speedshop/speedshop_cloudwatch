# frozen_string_literal: true

require "test_helper"

class CloudwatchTest < SpeedshopCloudwatchTest
  def test_configure_yields_configuration
    yielded_config = nil
    result = Speedshop::Cloudwatch.configure do |config|
      yielded_config = config
    end

    assert_kind_of Speedshop::Cloudwatch::Config, yielded_config
    assert_kind_of Speedshop::Cloudwatch::Config, result
  end

  def test_configure_allows_setting_options
    config = Speedshop::Cloudwatch.configure do |c|
      c.interval = 120
    end

    assert_equal 120, config.interval
  end

  def test_config_returns_configuration_instance
    config = Speedshop::Cloudwatch.config
    assert_kind_of Speedshop::Cloudwatch::Config, config
  end

  def test_reporter_returns_metric_reporter_instance
    Speedshop::Cloudwatch.configure do |config|
      config.client = Minitest::Mock.new
      config.logger = Logger.new(nil)
    end

    reporter = Speedshop::Cloudwatch.reporter
    assert_kind_of Speedshop::Cloudwatch::Reporter, reporter
  end
end
