# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        safe_report_latency
        yield
      end

      private

      def safe_report_latency
        report_latency if enqueued_at
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect ActiveJob metrics: #{e.message}", e)
      end

      def report_latency
        Reporter.instance.report(
          metric: :QueueLatency,
          value: calculate_latency,
          dimensions: {QueueName: queue_name},
          integration: :active_job
        )
      end

      def calculate_latency
        Time.now.to_f - enqueued_at.to_f
      end
    end
  end
end
