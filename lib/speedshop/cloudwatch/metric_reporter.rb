# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricReporter
      def initialize(config:)
        raise ArgumentError, "CloudWatch client must be provided" unless config.client
        @interval = config.interval
        @client = config.client
        @config = config
        @logger = config.logger
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
          unless any_integration_enabled?
            @logger.info "Speedshop::Cloudwatch: No integrations enabled, not starting reporter"
            return
          end
          @logger.info "Speedshop::Cloudwatch: Starting metric reporter (interval: #{@interval}s)"
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
          @logger.info "Speedshop::Cloudwatch: Stopping metric reporter"
          @running = false
          @thread&.join
          @thread = nil
          @pid = nil
        end
      end

      def report(metric_name, value, namespace:, unit: "None", dimensions: [])
        return unless metric_enabled?(metric_name, namespace)

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

      def any_integration_enabled?
        @config.enabled.values.any?
      end

      def metric_enabled?(metric_name, namespace)
        integration = namespace_to_integration(namespace)
        return true unless integration

        @config.enabled_integration?(integration) && @config.metrics[integration].include?(metric_name.to_sym)
      end

      def namespace_to_integration(namespace)
        @config.namespaces.each do |integration, ns|
          return integration if ns == namespace
        end
        nil
      end

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
        @logger.error "Speedshop::Cloudwatch: MetricReporter error: #{e.message}"
        @logger.debug e.backtrace.join("\n")
      end

      def collect_metrics
        @collectors.each do |collector|
          collector.call
        rescue => e
          @logger.error "Speedshop::Cloudwatch: Collector error: #{e.message}"
          @logger.debug e.backtrace.join("\n")
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

          @logger.debug "Speedshop::Cloudwatch: Sending #{metric_data.size} metrics to namespace #{namespace}"
          @client.put_metric_data(
            namespace: namespace,
            metric_data: metric_data
          )
        end
      rescue => e
        @logger.error "Speedshop::Cloudwatch: Failed to send metrics: #{e.message}"
        @logger.debug e.backtrace.join("\n")
      end
    end
  end
end
