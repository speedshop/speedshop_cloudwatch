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

  def test_enabled_environments_defaults_to_production
    @config.reset
    assert_equal ["production"], @config.enabled_environments
  end

  def test_allows_setting_enabled_environments
    @config.enabled_environments = ["production", "staging"]
    assert_equal ["production", "staging"], @config.enabled_environments
  end

  def test_environment_defaults_to_rails_env
    # The environment is set in detect_environment, which we test indirectly here
    refute_nil @config.environment
  end

  def test_allows_setting_environment
    @config.environment = "staging"
    assert_equal "staging", @config.environment
  end

  def test_environment_enabled_returns_true_when_environment_is_enabled
    @config.enabled_environments = ["production", "staging"]
    @config.environment = "staging"
    assert @config.environment_enabled?
  end

  def test_environment_enabled_returns_false_when_environment_is_not_enabled
    @config.enabled_environments = ["production"]
    @config.environment = "development"
    refute @config.environment_enabled?
  end
end
