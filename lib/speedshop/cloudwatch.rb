# frozen_string_literal: true

require "aws-sdk-cloudwatch"

module Speedshop
  module Cloudwatch
    class Error < StandardError; end
  end
end

require_relative "cloudwatch/active_job"
require_relative "cloudwatch/metric_reporter"
require_relative "cloudwatch/puma"
require_relative "cloudwatch/rack_middleware"
require_relative "cloudwatch/sidekiq"
require_relative "cloudwatch/version"
