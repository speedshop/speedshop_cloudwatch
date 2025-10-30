# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricReporter
      attr_reader :interval, :client

      def initialize(config:)
        raise ArgumentError, "CloudWatch client must be provided" unless config.client
        @interval = config.interval
        @client = config.client
        @thread = nil
        @pid = nil
        @running = false
        @mutex = Mutex.new
        @queue = []
        @collectors = []
      end

      def start!
        @mutex.synchronize do
          return if running_in_current_process?
          @pid = Process.pid
          @running = true
          @thread = Thread.new do
            Thread.current.thread_variable_set(:fork_safe, true)
            run_loop
          end
        end
      end

      def stop!
        @mutex.synchronize do
          @running = false
          @thread&.join
          @thread = nil
          @pid = nil
        end
      end

      def report(metric_name, value, namespace:, unit: "None", dimensions: [])
        @mutex.synchronize do
          @queue << {
            metric_name: metric_name,
            value: value,
            namespace: namespace,
            unit: unit,
            dimensions: dimensions,
            timestamp: Time.now
          }
        end
      end

      def register_collector(&block)
        @mutex.synchronize do
          @collectors << block
        end
      end

      private

      def running_in_current_process?
        @running && @pid == Process.pid
      end

      def run_loop
        while @running
          sleep @interval
          collect_metrics
          flush_metrics
        end
      rescue => e
        warn "MetricReporter error: #{e.message}"
      end

      def collect_metrics
        collectors = nil
        @mutex.synchronize do
          collectors = @collectors.dup
        end

        collectors.each do |collector|
          collector.call
        rescue => e
          warn "Collector error: #{e.message}"
        end
      end

      def flush_metrics
        metrics = nil
        @mutex.synchronize do
          return if @queue.empty?
          metrics = @queue.dup
          @queue.clear
        end

        metrics.group_by { |m| m[:namespace] }.each do |namespace, namespace_metrics|
          metric_data = namespace_metrics.map do |m|
            {
              metric_name: m[:metric_name],
              value: m[:value],
              unit: m[:unit],
              timestamp: m[:timestamp],
              dimensions: m[:dimensions]
            }
          end

          @client.put_metric_data(
            namespace: namespace,
            metric_data: metric_data
          )
        end
      rescue => e
        warn "Failed to send metrics: #{e.message}"
      end
    end
  end
end
