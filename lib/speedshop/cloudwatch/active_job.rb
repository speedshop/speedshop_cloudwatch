# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        begin
          if enqueued_at
            queue_time = Time.now.to_f - enqueued_at.to_f
            Cloudwatch.reporter.report(QueueLatency: queue_time, unit: "Seconds", dimensions: {JobClass: self.class.name, QueueName: queue_name})
          end
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect ActiveJob metrics: #{e.message}", e)
        end
        yield
      end
    end
  end
end
