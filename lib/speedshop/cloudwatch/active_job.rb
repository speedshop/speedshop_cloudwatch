# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        begin
          enqueued_at = self.enqueued_at

          if enqueued_at
            queue_time = Time.now.to_f - enqueued_at
            namespace = Speedshop::Cloudwatch.config.namespaces[:active_job]
            report("JobQueueTime", queue_time, namespace: namespace, unit: "Seconds", dimensions: job_dimensions)
          end
        rescue => e
          Speedshop.logger.error("Failed to report ActiveJob queue time: #{e.message}")
        end

        yield
      end

      private

      def report(*args, **kwargs)
        Cloudwatch.reporter.report(*args, **kwargs)
      end

      def job_dimensions
        [
          {name: "JobClass", value: self.class.name},
          {name: "QueueName", value: queue_name}
        ]
      end
    end
  end
end
