# frozen_string_literal: true

require "logger"

module Speedshop
  module Cloudwatch
    class Configuration
      attr_accessor :interval, :client, :enabled, :metrics, :namespaces, :logger, :sidekiq_queues

      def initialize
        @interval = 60
        @client = nil
        @enabled = {puma: true, sidekiq: true, rack: true, active_job: true}
        @metrics = {
          puma: [:Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads],
          sidekiq: [:EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs, :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity, :Utilization, :QueueLatency, :QueueSize],
          rack: [:RequestQueueTime],
          active_job: [:JobQueueTime]
        }
        @namespaces = {puma: "Puma", sidekiq: "Sidekiq", rack: "Rack", active_job: "ActiveJob"}
        @sidekiq_queues = nil
        @logger = (defined?(Rails) && Rails.respond_to?(:logger)) ? Rails.logger : Logger.new($stdout)
      end
    end
  end
end
