# frozen_string_literal: true

require "speedshop/cloudwatch"
require "speedshop/cloudwatch/railtie" if defined?(Rails::Railtie)

Speedshop::Cloudwatch.reporter.start!
