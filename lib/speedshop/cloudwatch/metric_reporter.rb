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
          return log_info("No integrations enabled, not starting reporter") unless @config.enabled.values.any?
          log_info("Starting metric reporter (interval: #{@config.interval}s)")
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
        @mutex.synchronize do
          log_info("Stopping metric reporter")
          @running = false
          @thread&.join
          @thread = @pid = nil
        end
      end

      def report(metric_name, value, namespace:, unit: "None", dimensions: [])
        integration = @config.namespaces.key(namespace)
        return if integration && !metric_allowed?(integration, metric_name)

        @mutex.synchronize do
          @queue << {metric_name: metric_name, value: value, namespace: namespace, unit: unit,
                     dimensions: dimensions, timestamp: Time.now}
        end
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
            rescue
              log_error("Collector error: #{$!.message}")
            end
          }
          flush_metrics
        end
      rescue => e
        log_error("MetricReporter error: #{e.message}")
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
        log_error("Failed to send metrics: #{e.message}")
      end

      def metric_allowed?(integration, metric_name)
        @config.enabled[integration] && @config.metrics[integration].include?(metric_name.to_sym)
      end

      def log_info(msg)
        @config.logger.info "Speedshop::Cloudwatch: #{msg}"
      end

      def log_error(msg)
        @config.logger.error "Speedshop::Cloudwatch: #{msg}"
        @config.logger.debug $!.backtrace.join("\n") if $!
      end
    end
  end
end
