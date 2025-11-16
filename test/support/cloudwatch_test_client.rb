# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class TestClient
      attr_reader :calls

      def initialize
        @calls = []
        @mutex = Mutex.new
      end

      # Mimics AWS CloudWatch Client interface
      def put_metric_data(namespace:, metric_data:)
        @mutex.synchronize do
          @calls << {
            namespace: namespace,
            metric_data: metric_data,
            timestamp: Time.now
          }
        end
      end

      # Test helper: Find specific metrics across all calls
      def find_metrics(metric_name: nil, namespace: nil)
        @mutex.synchronize do
          @calls.flat_map do |call|
            next [] if namespace && call[:namespace] != namespace

            call[:metric_data].select do |m|
              metric_name.nil? || m[:metric_name] == metric_name.to_s
            end
          end
        end
      end

      # Test helper: Count total metrics sent
      def metric_count
        @mutex.synchronize do
          @calls.sum { |c| c[:metric_data].size }
        end
      end

      # Test helper: Get all metrics for a namespace
      def metrics_for_namespace(namespace)
        @mutex.synchronize do
          @calls
            .select { |c| c[:namespace] == namespace }
            .flat_map { |c| c[:metric_data] }
        end
      end

      # Test helper: Check if metric was sent
      def metric_sent?(metric_name, namespace: nil)
        !find_metrics(metric_name: metric_name, namespace: namespace).empty?
      end

      # Test helper: Get last call
      def last_call
        @mutex.synchronize { @calls.last }
      end

      # Test helper: Reset captured calls
      def reset!
        @mutex.synchronize { @calls.clear }
      end
    end
  end
end
