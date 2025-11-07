# frozen_string_literal: true

require "logger"
require "singleton"

module Speedshop
  module Cloudwatch
    class Config
      include Singleton

      attr_accessor :interval, :metrics, :namespaces, :logger, :sidekiq_queues, :dimensions, :units, :collectors
      attr_writer :client

      def initialize
        reset
      end

      def client
        @client ||= Aws::CloudWatch::Client.new
      end

      def reset
        @interval = 60
        @client = nil
        @metrics = {
          puma: [],
          sidekiq: [:QueueLatency],
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
        @collectors = [] # [:puma, :sidekiq]
      end

      def self.reset
        if instance_variable_defined?(:@singleton__instance__)
          config = instance_variable_get(:@singleton__instance__)
          config&.reset
        end
        instance_variable_set(:@singleton__instance__, nil)
      end
    end
  end
end
