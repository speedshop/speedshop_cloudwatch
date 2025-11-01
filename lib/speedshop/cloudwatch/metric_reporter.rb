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
        @registered_integrations = Set.new
        @thread = @pid = nil
        @running = false
      end

      def start!
        return if started?

        @mutex.synchronize do
          return if started?
          return Speedshop::Cloudwatch.log_info("No integrations registered, not starting reporter") if @collectors.empty?
          Speedshop::Cloudwatch.log_info("Starting metric reporter (interval: #{@config.interval}s)")
          # Puma and Sidekiq Swarm both fork. We need to safely deal with that.
          # After a fork, the background thread is dead, so we start a new one.
          # We track the pid to know if we've forked.
          @pid = Process.pid
          @running = true
          @thread = Thread.new do
            # This bit is to tell Puma that this thread is fork-safe, so it won't
            # log anything.
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

      def report(**kwargs)
        dimensions = kwargs.delete(:dimensions) || {}
        unit = kwargs.delete(:unit) || "None"

        raise ArgumentError, "Expected exactly one metric" unless kwargs.size == 1
        metric_name, value = kwargs.first

        integration = find_integration_for_metric(metric_name)
        return unless integration

        namespace = @config.namespaces[integration]

        if [:rack, :active_job].include?(integration)
          @mutex.synchronize { @registered_integrations << integration }
        end

        return unless metric_allowed?(integration, metric_name)

        dimensions_array = convert_dimensions(dimensions)
        all_dimensions = dimensions_array + custom_dimensions

        @mutex.synchronize do
          @queue << {metric_name: metric_name.to_s, value: value, namespace: namespace, unit: unit,
                     dimensions: all_dimensions, timestamp: Time.now}
        end

        start! unless started?
      end

      def register_collector(integration, &block)
        @mutex.synchronize do
          @collectors << {integration: integration, block: block}
          @registered_integrations << integration
        end
      end

      def unregister_collector(integration)
        @mutex.synchronize do
          @collectors.reject! { |c| c[:integration] == integration }
          @registered_integrations.delete(integration)
        end
      end

      def clear_all
        @mutex.synchronize do
          @queue.clear
          @collectors.clear
          @registered_integrations.clear
        end
      end

      private

      def run_loop
        while @running
          sleep @config.interval
          @collectors.each { |c|
            begin
              c[:block].call
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

        # We batch these up as much as we can to minimize API calls
        metrics.group_by { |m| m[:namespace] }.each do |namespace, ns_metrics|
          @config.logger.debug "Speedshop::Cloudwatch: Sending #{ns_metrics.size} metrics to namespace #{namespace}"
          metric_data = ns_metrics.map { |m| m.slice(:metric_name, :value, :unit, :timestamp, :dimensions) }
          @config.client.put_metric_data(namespace: namespace, metric_data: metric_data)
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def metric_allowed?(integration, metric_name)
        @registered_integrations.include?(integration) && @config.metrics[integration].include?(metric_name.to_sym)
      end

      def custom_dimensions
        @config.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end

      def find_integration_for_metric(metric_name)
        @config.metrics.find { |int, metrics| metrics.include?(metric_name.to_sym) }&.first
      end

      def convert_dimensions(dimensions)
        case dimensions
        when Hash
          dimensions.map { |k, v| {name: k.to_s, value: v.to_s} }
        when Array
          dimensions
        else
          []
        end
      end
    end
  end
end
