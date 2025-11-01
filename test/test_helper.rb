# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "speedshop/cloudwatch"
require "minitest/autorun"
require_relative "support/doubles"

class SpeedshopCloudwatchTest < Minitest::Test
  def setup
    @client = Minitest::Mock.new
    Speedshop::Cloudwatch.instance_variable_set(:@config, nil)
    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.logger = Logger.new(nil)
    end
    clear_reporter_state
  end

  def teardown
    clear_reporter_state
    Speedshop::Cloudwatch.remove_instance_variable(:@config) if Speedshop::Cloudwatch.instance_variable_defined?(:@config)
    Speedshop::Cloudwatch.remove_instance_variable(:@reporter) if Speedshop::Cloudwatch.instance_variable_defined?(:@reporter)
  end

  private

  def clear_reporter_state
    return unless Speedshop::Cloudwatch.instance_variable_defined?(:@reporter)
    reporter = Speedshop::Cloudwatch.instance_variable_get(:@reporter)
    reporter&.clear_all
  end
end
