# frozen_string_literal: true

require "test_helper"
require "puma"

class PumaTest < Minitest::Test
  def test_puma_integration_is_defined
    assert defined?(Speedshop::Cloudwatch::Puma)
  end

  def test_can_register_collector
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

    reporter = Speedshop::Cloudwatch::MetricReporter.new(
      config: Speedshop::Cloudwatch::Configuration.new.tap do |c|
        c.client = client
        c.interval = 60
      end
    )

    ::Puma.stub(:stats_hash, stub_puma_stats) do
      Speedshop::Cloudwatch::Puma.register(namespace: "Puma", reporter: reporter)
    end
  end
end
