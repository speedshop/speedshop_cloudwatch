# frozen_string_literal: true

require "aws-sdk-cloudwatch"
require "monitor"
require "speedshop/cloudwatch/active_job"
require "speedshop/cloudwatch/configuration"
require "speedshop/cloudwatch/metric_reporter"
require "speedshop/cloudwatch/puma"
require "speedshop/cloudwatch/rack_middleware"
require "speedshop/cloudwatch/sidekiq"
require "speedshop/cloudwatch/version"

module Speedshop
  module Cloudwatch
    class Error < StandardError; end
    @monitor = Monitor.new

    class << self
      attr_reader :monitor

      def configure
        @monitor.synchronize do
          @config ||= Configuration.new
          yield @config if block_given?
          @config
        end
      end

      def config
        return @config if defined?(@config) && @config
        @monitor.synchronize { @config ||= Configuration.new }
      end

      def config=(value)
        @monitor.synchronize { @config = value }
      end

      def reporter
        return @reporter if defined?(@reporter) && @reporter
        @reporter = MetricReporter.new(config: config)
      end

      def reporter=(value)
        @monitor.synchronize { @reporter = value }
      end

      def log_info(msg)
        config.logger.info "Speedshop::Cloudwatch: #{msg}"
      end

      def log_error(msg, exception = nil)
        config.logger.error "Speedshop::Cloudwatch: #{msg}"
        config.logger.debug exception.backtrace.join("\n") if exception&.backtrace
      end
    end
  end
end
