# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "speedshop/cloudwatch"
require "minitest/autorun"
require "webmock/minitest"
require_relative "support/doubles"

class SpeedshopCloudwatchTest < Minitest::Test
  def setup
    reset_singletons
    WebMock.disable_net_connect!
    stub_request(:post, /monitoring\..*\.amazonaws\.com/).to_return(status: 200, body: "{}")
    Speedshop::Cloudwatch.configure do |config|
      config.client = Aws::CloudWatch::Client.new(region: "us-east-1", stub_responses: true)
      config.interval = 0.1
      config.logger = Logger.new(nil)
    end
  end

  def teardown
    reset_singletons
    WebMock.reset!
  end

  private

  def reset_singletons
    reset_reporter
    reset_config
    reset_integrations
  end

  def reset_reporter
    Speedshop::Cloudwatch::Reporter.reset
  end

  def reset_config
    Speedshop::Cloudwatch::Config.reset
  end

  def reset_integrations
    Speedshop::Cloudwatch::Integration.clear_integrations
    Speedshop::Cloudwatch::Integration.add_integration(:puma, Speedshop::Cloudwatch::Puma::MetricsCollector)
    Speedshop::Cloudwatch::Integration.add_integration(:sidekiq, Speedshop::Cloudwatch::Sidekiq::MetricsCollector)
  end
end
