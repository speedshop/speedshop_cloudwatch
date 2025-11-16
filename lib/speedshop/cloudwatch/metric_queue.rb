# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class MetricQueue
      def initialize(max_size:)
        @queue = []
        @mutex = Mutex.new
        @max_size = max_size
        @dropped_count = 0
      end

      def push(metric)
        @mutex.synchronize do
          handle_overflow
          @queue << metric
        end
      end

      def drain
        @mutex.synchronize do
          return nil if @queue.empty?

          drained = @queue
          @queue = []
          drained
        end
      end

      def clear
        @mutex.synchronize { @queue.clear }
      end

      def dropped_since_last_check
        @mutex.synchronize do
          count = @dropped_count
          @dropped_count = 0
          count
        end
      end

      private

      def handle_overflow
        return unless overflow?

        @queue.shift
        @dropped_count += 1
      end

      def overflow?
        @queue.size >= @max_size
      end
    end
  end
end
