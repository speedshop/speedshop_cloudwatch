# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/api"

class SidekiqTest < Minitest::Test
  def teardown
    Speedshop::Cloudwatch::Sidekiq.stop!
  end

  def test_sidekiq_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Sidekiq)
  end

  def test_can_start_and_stop
    client = Minitest::Mock.new

    stats_mock = Minitest::Mock.new
    stats_mock.expect(:enqueued, 10)
    stats_mock.expect(:processed, 100)
    stats_mock.expect(:failed, 5)
    stats_mock.expect(:scheduled_size, 2)
    stats_mock.expect(:retry_size, 3)
    stats_mock.expect(:dead_size, 1)
    stats_mock.expect(:workers_size, 4)

    queue_mock = Minitest::Mock.new
    queue_mock.expect(:name, "default")
    queue_mock.expect(:latency, 1.5)
    queue_mock.expect(:size, 20)

    ::Sidekiq::Stats.stub(:new, stats_mock) do
      ::Sidekiq::Queue.stub(:all, [queue_mock]) do
        Speedshop::Cloudwatch::Sidekiq.start!(interval: 60, client: client)
        Speedshop::Cloudwatch::Sidekiq.stop!
      end
    end
  end
end
