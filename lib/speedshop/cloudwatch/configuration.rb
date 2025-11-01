# frozen_string_literal: true

require "logger"

module Speedshop
  module Cloudwatch
    class Configuration
      attr_accessor :interval, :client, :metrics, :namespaces, :logger, :sidekiq_queues, :dimensions, :units

      def initialize
        @interval = 60
        @client = nil
        @metrics = {
          puma: [:Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads],
          sidekiq: [
            :EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs, :DeadJobs,
            :Workers, :Processes, :DefaultQueueLatency, :Capacity, :Utilization, :QueueLatency, :QueueSize
          ],
          rack: [:RequestQueueTime],
          active_job: [:QueueLatency]
        }
        @units = {
          Workers: "Count", BootedWorkers: "Count", OldWorkers: "Count", Running: "Count",
          Backlog: "Count", PoolCapacity: "Count", MaxThreads: "Count",
          EnqueuedJobs: "Count", ProcessedJobs: "Count", FailedJobs: "Count",
          ScheduledJobs: "Count", RetryJobs: "Count", DeadJobs: "Count",
          Processes: "Count", Capacity: "Count", QueueSize: "Count",
          DefaultQueueLatency: "Seconds", QueueLatency: "Seconds",
          Utilization: "Percent",
          RequestQueueTime: "Milliseconds"
        }
        @namespaces = {puma: "Puma", sidekiq: "Sidekiq", rack: "Rack", active_job: "ActiveJob"}
        @sidekiq_queues = nil
        @dimensions = {}
        @logger = (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger) ? Rails.logger : Logger.new($stdout)
      end
    end
  end
end
