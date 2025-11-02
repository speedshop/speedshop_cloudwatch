# frozen_string_literal: true

require "test_helper"

class ConfigTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch::Config.instance
  end

  def test_allows_setting_custom_interval
    @config.interval = 120
    assert_equal 120, @config.interval
  end

  def test_allows_setting_custom_client
    client = Object.new
    @config.client = client
    assert_same client, @config.client
  end

  def test_allows_customizing_metrics
    @config.metrics[:puma] = [:Workers, :Running]
    assert_equal [:Workers, :Running], @config.metrics[:puma]
  end

  def test_allows_customizing_namespaces
    @config.namespaces[:puma] = "MyApp/Puma"
    assert_equal "MyApp/Puma", @config.namespaces[:puma]
  end

  def test_allows_setting_sidekiq_queues
    @config.sidekiq_queues = ["critical", "default"]
    assert_equal ["critical", "default"], @config.sidekiq_queues
  end

  def test_allows_setting_custom_logger
    custom_logger = Logger.new(nil)
    @config.logger = custom_logger
    assert_same custom_logger, @config.logger
  end

  def test_dimensions_defaults_to_empty_hash
    assert_equal({}, @config.dimensions)
  end

  def test_allows_setting_custom_dimensions
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    assert_equal({ServiceName: "myservice-api", Environment: "production"}, @config.dimensions)
  end
end
