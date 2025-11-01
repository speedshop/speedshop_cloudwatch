# frozen_string_literal: true

require "test_helper"
require "rack"

class RackMiddlewareTest < SpeedshopCloudwatchTest
  def setup
    super
    @app = ->(env) { [200, {}, ["OK"]] }
  end

  def teardown
    @middleware = nil
    super
  end

  private

  def configure_cloudwatch_for_test(**overrides)
    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.logger = Logger.new(nil)
      overrides.each { |k, v| config.public_send(:"#{k}=", v) }
    end
  end

  def call_middleware_with_header(header_name, queue_start_ms_ago: 100)
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)
    queue_start = (Time.now.to_f * 1000) - queue_start_ms_ago
    env = {header_name => "t=#{queue_start}"}
    @middleware.call(env)
  end

  public

  def test_processes_request_with_x_request_start
    status, _headers, _body = call_middleware_with_header("HTTP_X_REQUEST_START")
    assert_equal 200, status
  end

  def test_processes_request_with_x_queue_start
    status, _headers, _body = call_middleware_with_header("HTTP_X_QUEUE_START")
    assert_equal 200, status
  end

  def test_handles_missing_queue_header
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app)

    env = {}
    status, _headers, _body = @middleware.call(env)

    assert_equal 200, status
  end

  def test_errors_during_metric_reporting_do_not_prevent_response
    configure_cloudwatch_for_test
    reporter = Speedshop::Cloudwatch.reporter
    reporter.stub :report, ->(*) { raise "Metric reporting error" } do
      status, _headers, _body = call_middleware_with_header("HTTP_X_REQUEST_START")
      assert_equal 200, status
    end
  end

  def test_uses_configured_namespace
    Speedshop::Cloudwatch.configure do |config|
      config.client = @client
      config.interval = 60
      config.namespaces[:rack] = "MyApp/Rack"
    end

    reporter = Speedshop::Cloudwatch.reporter

    reported_namespace = nil
    reporter.stub :report, ->(metric_name, value, namespace:, **kwargs) { reported_namespace = namespace } do
      call_middleware_with_header("HTTP_X_REQUEST_START")
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
