# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        enqueued_at = self.enqueued_at

        if enqueued_at
          queue_time = Time.now.to_f - enqueued_at
          namespace = Speedshop::Cloudwatch.config.namespaces[:active_job]
          report("job_queue_time", queue_time, namespace: namespace, unit: "Seconds", dimensions: job_dimensions)
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
