# frozen_string_literal: true

require "aws-sdk-cloudwatch"
require "speedshop/cloudwatch/configuration"
require "speedshop/cloudwatch/integration"
require "speedshop/cloudwatch/metrics_collector"
require "speedshop/cloudwatch/metric_reporter"
require "speedshop/cloudwatch/active_job"
require "speedshop/cloudwatch/puma"
require "speedshop/cloudwatch/rack_middleware"
require "speedshop/cloudwatch/sidekiq"
require "speedshop/cloudwatch/version"

module Speedshop
  module Cloudwatch
    class Error < StandardError; end

    class << self
      def configure
        yield Config.instance if block_given?
        Config.instance
      end

      def config
        Config.instance
      end

      def reporter
        Reporter.instance
      end

      def add_integration(name, collector_class, config: nil)
        Integration.add_integration(name, collector_class, config: config)
      end

      def log_info(msg)
        Config.instance.logger.info "Speedshop::Cloudwatch: #{msg}"
      end

      def log_error(msg, exception = nil)
        Config.instance.logger.error "Speedshop::Cloudwatch: #{msg}"
        Config.instance.logger.debug exception.backtrace.join("\n") if exception&.backtrace
      end
    end
  end
end
