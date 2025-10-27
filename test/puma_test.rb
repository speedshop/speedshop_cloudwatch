# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < Minitest::Test
  def teardown
    Speedshop::Cloudwatch::Puma.stop!
  end

  def test_puma_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Puma)
  end

  def test_can_start_and_stop
    client = Minitest::Mock.new

    stub_puma_stats = {
      workers: 2,
      booted_workers: 2,
      old_workers: 0,
      running: 5,
      backlog: 0,
      pool_capacity: 5,
      max_threads: 5
    }

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.start!(interval: 60, client: client)
      Speedshop::Cloudwatch::Puma.stop!
    end
  end
end
