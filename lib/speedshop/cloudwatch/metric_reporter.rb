# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricReporter
      attr_reader :namespace, :interval, :client

      def initialize(namespace:, interval: 60, client: nil)
        @namespace = namespace
        @interval = interval
        @client = client || Aws::CloudWatch::Client.new
        @thread = nil
        @running = false
        @mutex = Mutex.new
        @queue = []
      end

      def start!
        @mutex.synchronize do
          return if @running
          @running = true
          @thread = Thread.new { run_loop }
        end
      end

      def stop!
        @mutex.synchronize do
          @running = false
          @thread&.join
          @thread = nil
        end
      end

      def report(metric_name, value, unit: "None", dimensions: [])
        @mutex.synchronize do
          @queue << {
            metric_name: metric_name,
            value: value,
            unit: unit,
            dimensions: dimensions,
            timestamp: Time.now
          }
        end
      end

      private

      def run_loop
        while @running
          sleep @interval
          flush_metrics
        end
      rescue => e
        warn "MetricReporter error: #{e.message}"
      end

      def flush_metrics
        metrics = nil
        @mutex.synchronize do
          return if @queue.empty?
          metrics = @queue.dup
          @queue.clear
        end

        metric_data = metrics.map do |m|
          {
            metric_name: m[:metric_name],
            value: m[:value],
            unit: m[:unit],
            timestamp: m[:timestamp],
            dimensions: m[:dimensions]
          }
        end

        @client.put_metric_data(
          namespace: @namespace,
          metric_data: metric_data
        )
      rescue => e
        warn "Failed to send metrics: #{e.message}"
      end
    end
  end
end
