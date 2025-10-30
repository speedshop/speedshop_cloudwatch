# frozen_string_literal: true

require "logger"

module Speedshop
  module Cloudwatch
    class Configuration
      attr_accessor :interval, :client, :enabled, :metrics, :namespaces, :logger, :sidekiq_queues

      def initialize
        @interval = 60
        @client = nil
        @enabled = {
          puma: true,
          sidekiq: true,
          rack: true,
          active_job: true
        }
        @metrics = {
          puma: [:workers, :booted_workers, :old_workers, :running, :backlog, :pool_capacity, :max_threads],
          sidekiq: [:EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs, :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity, :Utilization, :QueueLatency, :QueueSize],
          rack: [:request_queue_time],
          active_job: [:job_queue_time]
        }
        @namespaces = {
          puma: "Puma",
          sidekiq: "Sidekiq",
          rack: "Rack",
          active_job: "ActiveJob"
        }
        @sidekiq_queues = nil
        @logger = default_logger
      end

      def enabled_integration?(integration)
        @enabled[integration]
      end

      private

      def default_logger
        if defined?(Rails) && Rails.respond_to?(:logger)
          Rails.logger
        else
          Logger.new($stdout)
        end
      end
    end
  end
end
