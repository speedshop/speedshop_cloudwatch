# frozen_string_literal: true

require "singleton"

module Speedshop
  module Cloudwatch
    class Reporter
      include Singleton

      attr_reader :queue, :running, :thread
      attr_accessor :pid

      def initialize
        @mutex = Mutex.new
        @queue = []
        @collectors = []
        @thread = @pid = nil
        @running = false
        @on_demand_integrations = Set.new
      end

      def start!
        return if started?
        return if skip_start?

        @mutex.synchronize do
          return if started?

          config = Config.instance
          raise ArgumentError, "CloudWatch client must be provided" unless config.client

          initialize_collectors
          return Speedshop::Cloudwatch.log_info("No integrations enabled, not starting reporter") if @collectors.empty?

          Speedshop::Cloudwatch.log_info("Starting metric reporter (interval: #{config.interval}s)")
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
          @collectors.clear
        end
        thread_to_join&.join
      end

      def report(metric:, value:, dimensions: {}, namespace: nil)
        config = Config.instance
        metric_name = metric.to_sym

        integration = find_integration_for_metric(metric_name)
        return unless integration

        ns = namespace || config.namespaces[integration]
        unit = config.units[metric_name] || "None"

        if [:rack, :active_job].include?(integration)
          @mutex.synchronize { @on_demand_integrations << integration }
        end

        return unless metric_allowed?(integration, metric_name)

        dimensions_array = dimensions.map { |k, v| {name: k.to_s, value: v.to_s} }
        all_dimensions = dimensions_array + custom_dimensions

        @mutex.synchronize do
          @queue << {metric_name: metric_name.to_s, value: value, namespace: ns, unit: unit,
                     dimensions: all_dimensions, timestamp: Time.now}
        end

        start! unless started?
      end

      def clear_all
        @mutex.synchronize do
          @queue.clear
          @collectors.clear
          @on_demand_integrations.clear
        end
      end

      def enable_integration(integration)
        @mutex.synchronize { @on_demand_integrations << integration }
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

      def skip_start?
        if defined?(Rails::Console)
          Speedshop::Cloudwatch.log_info("Skipping reporter start in Rails console")
          return true
        end

        if defined?(Rails::Command::RunnerCommand)
          Speedshop::Cloudwatch.log_info("Skipping reporter start in Rails runner")
          return true
        end

        if defined?(Rake) && defined?(Rake.application) && Rake.respond_to?(:application) &&
            Rake.application.top_level_tasks.any? { |t| t.match?(/^(assets:|db:|webpacker:)/) }
          Speedshop::Cloudwatch.log_info("Skipping reporter start in Rake task")
          return true
        end

        false
      end

      def initialize_collectors
        Integration.integrations.each do |integration|
          next unless integration.collector_class.collect?(Config.instance)
          @collectors << integration.collector_class.new
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to initialize collector for #{integration.name}: #{e.message}", e)
        end
      end

      def run_loop
        config = Config.instance
        while @running
          (config.interval / 0.1).to_i.times do
            break unless @running
            sleep 0.1
          end
          break unless @running
          collect_metrics
          flush_metrics
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Reporter error: #{e.message}", e)
      end

      def collect_metrics
        @collectors.each do |collector|
          collector.collect
        rescue => e
          Speedshop::Cloudwatch.log_error("Collector error: #{e.message}", e)
        end
      end

      def flush_metrics
        config = Config.instance
        metrics = @mutex.synchronize { @queue.empty? ? nil : @queue.dup.tap { @queue.clear } }
        return unless metrics

        metrics.group_by { |m| m[:namespace] }.each do |namespace, ns_metrics|
          config.logger.debug "Speedshop::Cloudwatch: Sending #{ns_metrics.size} metrics to namespace #{namespace}"
          metric_data = ns_metrics.map { |m| m.slice(:metric_name, :value, :unit, :timestamp, :dimensions) }
          config.client.put_metric_data(namespace: namespace, metric_data: metric_data)
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def metric_allowed?(integration, metric_name)
        config = Config.instance
        (@collectors.any? || @on_demand_integrations.include?(integration)) &&
          config.metrics[integration].include?(metric_name.to_sym)
      end

      def custom_dimensions
        Config.instance.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end

      def find_integration_for_metric(metric_name)
        Config.instance.metrics.find { |int, metrics| metrics.include?(metric_name.to_sym) }&.first
      end
    end

    MetricReporter = Reporter
  end
end
