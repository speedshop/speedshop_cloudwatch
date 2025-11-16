# frozen_string_literal: true

require "singleton"
require_relative "metric_queue"
require_relative "metric_builder"
require_relative "metric_aggregator"

module Speedshop
  module Cloudwatch
    class Reporter
      include Singleton

      def initialize
        @mutex = Mutex.new
        @condition_variable = ConditionVariable.new
        @queue = nil
        @builder = nil
        @aggregator = nil
        @collectors = []
        @thread = nil
        @pid = Process.pid
        @running = false
      end

      def start!
        return unless should_start?

        @mutex.synchronize do
          return if started?

          initialize_dependencies
          handle_fork if forked?
          start_reporter_thread
        end
      end

      def started?
        @running && @thread&.alive?
      end

      def stop!
        thread = prepare_shutdown
        return unless thread

        wait_for_thread(thread)
      end

      def report(metric:, value: nil, statistic_values: nil, dimensions: {}, namespace: nil, integration: nil)
        return unless config.environment_enabled?

        datum = builder.build_datum(
          metric: metric, value: value,
          statistic_values: statistic_values,
          dimensions: dimensions,
          namespace: namespace, integration: integration
        )
        return unless datum

        queue.push(datum)
        start! unless started?
      end

      def clear_all
        @mutex.synchronize do
          queue.clear
          @collectors.clear
        end
      end

      def flush_now!
        return unless @running

        collect_and_flush
      end

      # Test helper: Simulate fork by setting a different PID
      def test_set_pid(pid)
        @pid = pid
      end

      # Test helper: Get the reporter thread for testing
      def test_get_thread
        @thread
      end

      def self.reset
        if instance_variable_defined?(:@singleton__instance__)
          reporter = instance_variable_get(:@singleton__instance__)
          reporter&.stop! if reporter&.started?
          reporter&.clear_all
        end
        instance_variable_set(:@singleton__instance__, nil)
      end

      private

      def config
        Config.instance
      end

      def queue
        @queue ||= MetricQueue.new(max_size: config.queue_max_size)
      end

      def builder
        @builder ||= MetricBuilder.new(config: config)
      end

      def aggregator
        @aggregator ||= MetricAggregator.new
      end

      def should_start?
        config.environment_enabled? && !started?
      end

      def forked?
        @pid != Process.pid
      end

      def initialize_dependencies
        queue
        builder
        aggregator
        initialize_collectors
      end

      def handle_fork
        @collectors.clear
        queue.clear
      end

      def start_reporter_thread
        log_start
        @running = true
        @thread = create_thread
      end

      def create_thread
        Thread.new do
          Thread.current.thread_variable_set(:fork_safe, true)
          Thread.current.name = "scw_reporter"
          run_loop
        end
      end

      def log_start
        collectors = @collectors.map(&:class).join(", ")
        Speedshop::Cloudwatch.log_info("Starting metric reporter (collectors: #{collectors})")
      end

      def initialize_collectors
        config.collectors.each { |int| add_collector(int) }
      end

      def add_collector(integration)
        @collectors << create_collector(integration)
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to initialize collector for #{integration}: #{e.message}", e)
      end

      def create_collector(integration)
        return Speedshop::Cloudwatch::Puma.new if integration == :puma
        Speedshop::Cloudwatch::Sidekiq.new if integration == :sidekiq
      end

      def prepare_shutdown
        @mutex.synchronize do
          return nil unless @running

          Speedshop::Cloudwatch.log_info("Stopping metric reporter")
          @running = false
          @condition_variable.signal
          @thread.tap {
            @thread = @pid = nil
            @collectors.clear
          }
        end
      end

      def wait_for_thread(thread)
        thread.join(2) ?
          log_graceful_shutdown :
          log_timeout
      end

      def log_graceful_shutdown
        Speedshop::Cloudwatch.log_info("Reporter thread stopped gracefully")
      end

      def log_timeout
        Speedshop::Cloudwatch.log_info("Reporter thread did not finish within 2s timeout")
      end

      def run_loop
        loop do
          break unless wait_for_interval
          collect_and_flush
        end
        collect_and_flush
      rescue => e
        Speedshop::Cloudwatch.log_error("Reporter error: #{e.message}", e)
      end

      def wait_for_interval
        @mutex.synchronize do
          @condition_variable.wait(@mutex, config.interval) if @running
        end
        @running
      end

      def collect_and_flush
        collect_metrics
        flush_metrics
      end

      def collect_metrics
        @collectors.each { |c| safe_collect(c) }
      end

      def safe_collect(collector)
        collector.collect
      rescue => e
        Speedshop::Cloudwatch.log_error("Collector error: #{e.message}", e)
      end

      def flush_metrics
        metrics = queue.drain
        log_overflow
        return unless metrics

        flush_by_namespace(metrics)
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def flush_by_namespace(metrics)
        high_res = high_resolution?
        metrics.group_by { |m| m[:namespace] }.each do |ns, ms|
          send_namespace(ns, ms, high_res)
        end
      end

      def high_resolution?
        config.interval.to_i < 60
      end

      def send_namespace(namespace, metrics, high_res)
        log_send(namespace, metrics.size)
        aggregated = aggregator.aggregate(metrics)
        data = builder.build_for_cloudwatch(aggregated, high_resolution: high_res)
        send_to_cloudwatch(namespace, data)
      end

      def log_send(namespace, count)
        config.logger.debug "Speedshop::Cloudwatch: Sending #{count} metrics to namespace #{namespace}"
      end

      def send_to_cloudwatch(namespace, data)
        data.each_slice(20) do |batch|
          config.client.put_metric_data(namespace: namespace, metric_data: batch)
        end
      end

      def log_overflow
        dropped = queue.dropped_since_last_check
        return unless dropped > 0

        Speedshop::Cloudwatch.log_error("Queue overflow: dropped #{dropped} oldest metric(s) (max queue size: #{config.queue_max_size})")
      end
    end
  end
end
