# frozen_string_literal: true

require "aws-sdk-cloudwatch"
require "singleton"
require "speedshop/cloudwatch/active_job"
require "speedshop/cloudwatch/configuration"
require "speedshop/cloudwatch/metric_reporter"
require "speedshop/cloudwatch/puma"
require "speedshop/cloudwatch/rack_middleware"
require "speedshop/cloudwatch/railtie" if defined?(Rails::Railtie)
require "speedshop/cloudwatch/sidekiq"
require "speedshop/cloudwatch/version"

module Speedshop
  module Cloudwatch
    class Error < StandardError; end
    @reporter_mutex = Mutex.new

    class << self
      attr_reader :reporter_mutex

      def configure
        @config ||= Configuration.new
        yield @config if block_given?
        @config
      end

      def config
        @config ||= Configuration.new
      end

      def reporter
        return @reporter if defined?(@reporter)
        @reporter_mutex.synchronize { @reporter = MetricReporter.new(config: config) }
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
