# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        if enqueued_at
          queue_time = Time.now.to_f - enqueued_at
          Cloudwatch.reporter.report("JobQueueTime", queue_time, namespace: Speedshop::Cloudwatch.config.namespaces[:active_job],
            unit: "Seconds", dimensions: [{name: "JobClass", value: self.class.name}, {name: "QueueName", value: queue_name}])
        end rescue nil
        yield
      end
    end
  end
end
