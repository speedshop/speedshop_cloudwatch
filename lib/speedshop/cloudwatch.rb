# frozen_string_literal: true

require "aws-sdk-cloudwatch"
require "speedshop/cloudwatch/config"
require "speedshop/cloudwatch/reporter"
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

      def start!
        reporter.start!
      end

      def stop!
        reporter.stop!
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

at_exit do
  Speedshop::Cloudwatch.stop! if Speedshop::Cloudwatch.reporter.started?
end
