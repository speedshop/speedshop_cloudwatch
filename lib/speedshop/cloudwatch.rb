# frozen_string_literal: true

require "speedshop/cloudwatch/all"

module Speedshop
  module Cloudwatch
    @deprecation_warned ||= false
    unless @deprecation_warned
      log_info("DEPRECATION: require 'speedshop/cloudwatch/all' for current behavior, or require 'speedshop/cloudwatch/core' + specific integrations")
      @deprecation_warned = true
    end
  end
end
