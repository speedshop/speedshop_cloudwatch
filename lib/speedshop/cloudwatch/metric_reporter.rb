# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricReporter
      attr_reader :collectors, :queue, :running, :thread

      def initialize(config:)
        raise ArgumentError, "CloudWatch client must be provided" unless config.client
        @config = config
        @mutex = Mutex.new
        @queue = []
        @collectors = []
        @thread = @pid = nil
        @running = false
      end

      def start!
        return if started?

        @mutex.synchronize do
          return if started?
          return Speedshop::Cloudwatch.log_info("No integrations enabled, not starting reporter") unless @config.enabled.values.any?
          Speedshop::Cloudwatch.log_info("Starting metric reporter (interval: #{@config.interval}s)")
          @pid = Process.pid
          @running = true
          @thread = Thread.new do
            Thread.current.thread_variable_set(:fork_safe, true)
            run_loop
          end
        end
      end

      def started?
        @running && @pid == Process.pid && @thread&.alive?
      end

      def stop!
        thread_to_join = nil
        @mutex.synchronize do
          return unless @running
          Speedshop::Cloudwatch.log_info("Stopping metric reporter")
          @running = false
          thread_to_join = @thread
          @thread = @pid = nil
        end
        thread_to_join&.join
      end

      def report(metric_name, value, namespace:, unit: "None", dimensions: [])
        integration = @config.namespaces.key(namespace)
        return if integration && !metric_allowed?(integration, metric_name)

        all_dimensions = dimensions + custom_dimensions

        @mutex.synchronize do
          @queue << {metric_name: metric_name, value: value, namespace: namespace, unit: unit,
                     dimensions: all_dimensions, timestamp: Time.now}
        end

        start! unless started?
      end

      def register_collector(&block)
        @mutex.synchronize { @collectors << block }
      end

      private

      def run_loop
        while @running
          sleep @config.interval
          @collectors.each { |c|
            begin
              c.call
            rescue => e
              Speedshop::Cloudwatch.log_error("Collector error: #{e.message}", e)
            end
          }
          flush_metrics
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("MetricReporter error: #{e.message}", e)
      end

      def flush_metrics
        metrics = @mutex.synchronize { @queue.empty? ? nil : @queue.dup.tap { @queue.clear } }
        return unless metrics

        metrics.group_by { |m| m[:namespace] }.each do |namespace, ns_metrics|
          @config.logger.debug "Speedshop::Cloudwatch: Sending #{ns_metrics.size} metrics to namespace #{namespace}"
          metric_data = ns_metrics.map { |m| m.slice(:metric_name, :value, :unit, :timestamp, :dimensions) }
          @config.client.put_metric_data(namespace: namespace, metric_data: metric_data)
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def metric_allowed?(integration, metric_name)
        @config.enabled[integration] && @config.metrics[integration].include?(metric_name.to_sym)
      end

      def custom_dimensions
        @config.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end
    end
  end
end
