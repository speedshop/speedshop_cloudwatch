# frozen_string_literal: true

require "test_helper"
require "rack"

class RackMiddlewareTest < Minitest::Test
  def setup
    @app = ->(env) { [200, {}, ["OK"]] }
    @client = Minitest::Mock.new

    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.logger = Logger.new(nil)
    end
  end

  def teardown
    @middleware = nil
  end

  def test_processes_request_with_x_request_start
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    queue_start = (Time.now.to_f * 1000) - 100
    env = {"HTTP_X_REQUEST_START" => "t=#{queue_start}"}

    status, _headers, _body = @middleware.call(env)
    assert_equal 200, status
  end

  def test_processes_request_with_x_queue_start
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    queue_start = (Time.now.to_f * 1000) - 100
    env = {"HTTP_X_QUEUE_START" => "t=#{queue_start}"}

    status, _headers, _body = @middleware.call(env)
    assert_equal 200, status
  end

  def test_handles_missing_queue_header
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    env = {}
    status, _headers, _body = @middleware.call(env)

    assert_equal 200, status
  end

  def test_errors_during_metric_reporting_do_not_prevent_response
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.logger = Logger.new(nil)
    end

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(*) { raise "Metric reporting error" } do
      queue_start = (Time.now.to_f * 1000) - 100
      env = {"HTTP_X_REQUEST_START" => "t=#{queue_start}"}

      status, _headers, _body = @middleware.call(env)
      assert_equal 200, status
    end
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.namespaces[:rack] = "MyApp/Rack"
    end

    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)
    reporter = Speedshop::Cloudwatch.reporter

    reported_namespace = nil
    reporter.stub :report, ->(metric_name, value, namespace:, **kwargs) { reported_namespace = namespace } do
      queue_start = (Time.now.to_f * 1000) - 100
      env = {"HTTP_X_REQUEST_START" => "t=#{queue_start}"}
      @middleware.call(env)
    end

    assert_equal "MyApp/Rack", reported_namespace
  end

  def test_logs_error_when_collection_fails
    error_logged = false
    logger = Object.new
    logger.define_singleton_method(:error) { |msg| error_logged = true if msg.include?("Failed to collect Rack metrics") }
    logger.define_singleton_method(:debug) { |msg| }
    logger.define_singleton_method(:info) { |msg| }

    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.logger = logger
    end

    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(*) { raise "boom" } do
      env = {"HTTP_X_REQUEST_START" => "t=#{(Time.now.to_f * 1000) - 100}"}
      status, _headers, _body = @middleware.call(env)
      assert_equal 200, status
    end

    assert error_logged, "Expected error to be logged"
  end
end
