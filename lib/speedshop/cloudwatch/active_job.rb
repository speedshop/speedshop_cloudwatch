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
          queue_time = start_time - enqueued_at
          reporter.report("job_queue_time", queue_time, unit: "Seconds", dimensions: job_dimensions)
        end

        execution_time = Time.now - start_time
        reporter.report("job_execution_time", execution_time, unit: "Seconds", dimensions: job_dimensions)
      end

      def reporter
        @reporter ||= begin
          r = MetricReporter.new(namespace: "ActiveJob", interval: 60)
          r.start!
          r
        end
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
