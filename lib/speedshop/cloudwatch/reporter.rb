# frozen_string_literal: true

require "singleton"

module Speedshop
  module Cloudwatch
    class Reporter
      include Singleton

      def initialize
        @mutex = Mutex.new
        @condition_variable = ConditionVariable.new
        @queue = []
        @collectors = []
        @thread = nil
        @pid = Process.pid
        @running = false
        @dropped_since_last_flush = 0
        @last_overflow_log = nil
      end

      def start!
        return if !config.environment_enabled? || started?

        @mutex.synchronize do
          return if started?

          initialize_collectors
          if forked?
            @collectors.clear
            @queue.clear
          end

          Speedshop::Cloudwatch.log_info("Starting metric reporter (collectors: #{@collectors.map(&:class).join(", ")})")
          @running = true
          @thread = Thread.new do
            Thread.current.thread_variable_set(:fork_safe, true)
            Thread.current.name = "scw_reporter"
            run_loop
          end
        end
      end

      def started?
        @running && @thread&.alive?
      end

      def stop!
        thread_to_join = nil
        @mutex.synchronize do
          return unless @running
          Speedshop::Cloudwatch.log_info("Stopping metric reporter")
          @running = false
          @condition_variable.signal
          thread_to_join = @thread
          @thread = @pid = nil
          @collectors.clear
        end

        return unless thread_to_join

        result = thread_to_join.join(2)
        if result.nil?
          Speedshop::Cloudwatch.log_info("Reporter thread did not finish within 2s timeout")
        else
          Speedshop::Cloudwatch.log_info("Reporter thread stopped gracefully")
        end
      end

      def report(metric:, value: nil, statistic_values: nil, dimensions: {}, namespace: nil, integration: nil)
        return unless config.environment_enabled?

        metric_name = metric.to_sym

        int = integration || find_integration_for_metric(metric_name)
        return unless int

        ns = namespace || config.namespaces[int]
        unit = config.units[metric_name] || "None"

        return unless metric_allowed?(int, metric_name)

        dimensions_array = dimensions.map { |k, v| {name: k.to_s, value: v.to_s} }
        all_dimensions = dimensions_array + custom_dimensions

        datum = {metric_name: metric_name.to_s, namespace: ns, unit: unit,
                 dimensions: all_dimensions, timestamp: Time.now}
        if statistic_values
          datum[:statistic_values] = statistic_values
        else
          datum[:value] = value
        end

        @mutex.synchronize do
          if @queue.size >= config.queue_max_size
            @queue.shift
            @dropped_since_last_flush += 1
          end
          @queue << datum
        end

        start! unless started?
      end

      def clear_all
        @mutex.synchronize do
          @queue.clear
          @collectors.clear
        end
      end

      # Force immediate metrics collection and flush (for testing)
      # This bypasses the normal interval-based flushing
      def flush_now!
        return unless @running

        collect_metrics
        flush_metrics
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

      def forked?
        @pid != Process.pid
      end

      def initialize_collectors
        config.collectors.each do |integration|
          @collectors << Speedshop::Cloudwatch::Puma.new if integration == :puma
          @collectors << Speedshop::Cloudwatch::Sidekiq.new if integration == :sidekiq
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to initialize collector for #{integration}: #{e.message}", e)
        end
      end

      def run_loop
        while @running
          @mutex.synchronize do
            @condition_variable.wait(@mutex, config.interval) if @running
          end
          break unless @running
          collect_metrics
          flush_metrics
        end

        flush_metrics
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
        metrics = drain_queue
        log_overflow_if_needed
        return unless metrics

        high_resolution = config.interval.to_i < 60
        metrics.group_by { |m| m[:namespace] }.each do |namespace, ns_metrics|
          process_namespace(namespace, ns_metrics, high_resolution)
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def drain_queue
        buf = nil
        @mutex.synchronize do
          return nil if @queue.empty?
          buf = @queue
          @queue = []
        end
        buf
      end

      def process_namespace(namespace, ns_metrics, high_resolution)
        config.logger.debug "Speedshop::Cloudwatch: Sending #{ns_metrics.size} metrics to namespace #{namespace}"
        aggregated = aggregate_namespace_metrics(ns_metrics)
        metric_data = build_metric_data(aggregated, high_resolution)
        send_batches(namespace, metric_data)
      end

      def build_metric_data(aggregated, high_resolution)
        aggregated.map do |m|
          datum = {
            metric_name: m[:metric_name],
            unit: m[:unit],
            timestamp: m[:timestamp],
            dimensions: m[:dimensions]
          }
          if m[:statistic_values]
            datum[:statistic_values] = m[:statistic_values]
          else
            datum[:value] = m[:value]
          end
          datum[:storage_resolution] = 1 if high_resolution
          datum
        end
      end

      def send_batches(namespace, metric_data)
        metric_data.each_slice(20) do |batch|
          config.client.put_metric_data(namespace: namespace, metric_data: batch)
        end
      end

      def aggregate_namespace_metrics(ns_metrics)
        group_metrics(ns_metrics).map { |items| aggregate_group(items) }
      end

      def group_metrics(ns_metrics)
        groups = {}
        ns_metrics.each do |m|
          key = [m[:metric_name], m[:unit], normalized_dimensions_key(m[:dimensions])]
          (groups[key] ||= []) << m
        end
        groups.values
      end

      def aggregate_group(items)
        return items.first if items.size == 1

        sample_count, sum, minimum, maximum = aggregate_values(items)
        {
          metric_name: items.first[:metric_name],
          unit: items.first[:unit],
          dimensions: items.first[:dimensions],
          timestamp: Time.now,
          statistic_values: build_statistic_values(sample_count, sum, minimum, maximum)
        }
      end

      def aggregate_values(items)
        sample_count = 0.0
        sum = 0.0
        minimum = Float::INFINITY
        maximum = -Float::INFINITY

        items.each do |item|
          if item[:statistic_values]
            sv = item[:statistic_values]
            sc = sv[:sample_count].to_f
            sample_count += sc
            sum += sv[:sum].to_f
            minimum = [minimum, sv[:minimum].to_f].min
            maximum = [maximum, sv[:maximum].to_f].max
          elsif item.key?(:value)
            v = item[:value].to_f
            sample_count += 1.0
            sum += v
            minimum = [minimum, v].min
            maximum = [maximum, v].max
          end
        end

        [sample_count, sum, minimum, maximum]
      end

      def build_statistic_values(sample_count, sum, minimum, maximum)
        {
          sample_count: sample_count,
          sum: sum,
          minimum: minimum.finite? ? minimum : 0.0,
          maximum: maximum.finite? ? maximum : 0.0
        }
      end

      def normalized_dimensions_key(dims)
        (dims || []).sort_by { |d| d[:name].to_s }.map { |d| "#{d[:name]}=#{d[:value]}" }.join("|")
      end

      def metric_allowed?(integration, metric_name)
        config.metrics[integration].include?(metric_name.to_sym)
      end

      def custom_dimensions
        config.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end

      def find_integration_for_metric(metric_name)
        config.metrics.find { |int, metrics| metrics.include?(metric_name.to_sym) }&.first
      end

      def log_overflow_if_needed
        dropped = nil
        @mutex.synchronize do
          dropped = @dropped_since_last_flush
          @dropped_since_last_flush = 0
        end
        return unless dropped > 0

        Speedshop::Cloudwatch.log_error("Queue overflow: dropped #{dropped} oldest metric(s) (max queue size: #{config.queue_max_size})")
      end
    end
  end
end
