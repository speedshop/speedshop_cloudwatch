# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      private

      def report_job_metrics
        enqueued_at = self.enqueued_at
        start_time = Time.now

        yield

        if enqueued_at
          queue_time = start_time.to_f - enqueued_at
          report("job_queue_time", queue_time, namespace: "ActiveJob", unit: "Seconds", dimensions: job_dimensions)
        end

        execution_time = Time.now - start_time
        report("job_execution_time", execution_time, namespace: "ActiveJob", unit: "Seconds", dimensions: job_dimensions)
      end

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
