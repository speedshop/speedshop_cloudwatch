# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "speedshop/cloudwatch"
require "minitest/autorun"
require "webmock/minitest"
require_relative "support/doubles"
require_relative "support/cloudwatch_test_client"

class SpeedshopCloudwatchTest < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    stub_request(:post, /monitoring\..*\.amazonaws\.com/).to_return(status: 200, body: "{}")
    @test_client = Speedshop::Cloudwatch::TestClient.new
    Speedshop::Cloudwatch.configure do |config|
      config.client = @test_client
      config.interval = 0.1
      config.logger = Logger.new(nil)
      # Enable the reporter in test environment by default
      config.environment = "test"
      config.enabled_environments = ["test"]
    end
  end

  def teardown
    Speedshop::Cloudwatch::Reporter.reset
    Speedshop::Cloudwatch::Config.reset
    WebMock.reset!
  end
end
