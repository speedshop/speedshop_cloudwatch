# frozen_string_literal: true

require "logger"
require "singleton"

module Speedshop
  module Cloudwatch
    class Config
      include Singleton

      attr_accessor :interval, :metrics, :namespaces, :logger, :queue_max_size, :sidekiq_queues, :dimensions, :units,
        :collectors, :enabled_environments, :environment
      attr_writer :client

      def initialize
        reset
      end

      def client
        @client ||= Aws::CloudWatch::Client.new
      end

      def reset
        reset_basic_config
        reset_metrics_config
        reset_units
        reset_namespaces
        reset_advanced_config
      end

      def environment_enabled?
        enabled_environments.include?(environment)
      end

      def self.reset
        if instance_variable_defined?(:@singleton__instance__)
          config = instance_variable_get(:@singleton__instance__)
          config&.reset
        end
        instance_variable_set(:@singleton__instance__, nil)
      end

      private

      def reset_basic_config
        @interval = 60
        @queue_max_size = 1000
        @client = nil
      end

      def reset_metrics_config
        @metrics = {
          puma: [], sidekiq: [:QueueLatency],
          rack: [:RequestQueueTime], active_job: [:QueueLatency]
        }
      end

      def reset_units
        @units = default_units
      end

      def default_units
        count_units.merge(time_units).merge(Utilization: "Percent")
      end

      def count_units
        {
          Workers: "Count", BootedWorkers: "Count", OldWorkers: "Count",
          Running: "Count", Backlog: "Count", PoolCapacity: "Count",
          MaxThreads: "Count", EnqueuedJobs: "Count", ProcessedJobs: "Count",
          FailedJobs: "Count", ScheduledJobs: "Count", RetryJobs: "Count",
          DeadJobs: "Count", Processes: "Count", Capacity: "Count",
          QueueSize: "Count"
        }
      end

      def time_units
        {
          DefaultQueueLatency: "Seconds",
          QueueLatency: "Seconds",
          RequestQueueTime: "Milliseconds"
        }
      end

      def reset_namespaces
        @namespaces = {
          puma: "Puma", sidekiq: "Sidekiq",
          rack: "Rack", active_job: "ActiveJob"
        }
      end

      def reset_advanced_config
        @sidekiq_queues = nil
        @dimensions = {}
        @logger = default_logger
        @collectors = []
        @enabled_environments = ["production"]
        @environment = detect_environment
      end

      def default_logger
        (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger) ||
          Logger.new($stdout)
      end

      def detect_environment
        ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))
      end
    end
  end
end
