# frozen_string_literal: true

require "test_helper"
require "rack"

class RackMiddlewareTest < Minitest::Test
  def setup
    @app = ->(env) { [200, {}, ["OK"]] }
    @client = Minitest::Mock.new
  end

  def teardown
    @middleware = nil
  end

  def test_processes_request_with_x_request_start
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app, client: @client)

    queue_start = (Time.now.to_f * 1000) - 100
    env = {"HTTP_X_REQUEST_START" => "t=#{queue_start}"}

    status, _headers, _body = @middleware.call(env)
    assert_equal 200, status
  end

  def test_processes_request_with_x_queue_start
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app, client: @client)

    queue_start = (Time.now.to_f * 1000) - 100
    env = {"HTTP_X_QUEUE_START" => "t=#{queue_start}"}

    status, _headers, _body = @middleware.call(env)
    assert_equal 200, status
  end

  def test_handles_missing_queue_header
    @middleware = Speedshop::Cloudwatch::RackMiddleware.new(@app, client: @client)

    env = {}
    status, _headers, _body = @middleware.call(env)

    assert_equal 200, status
  end
end
