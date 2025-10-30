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

    class << self
      def configure
        @config ||= Configuration.new
        yield @config if block_given?
        @config
      end

      def config
        @config ||= Configuration.new
      end

      def reporter
        return @reporter if @reporter
        (@reporter_mutex ||= Mutex.new).synchronize { @reporter ||= MetricReporter.new(config: config) }
      end
    end
  end
end
