# frozen_string_literal: true

require "speedshop/cloudwatch"
require "speedshop/cloudwatch/active_job"
require "speedshop/cloudwatch/puma"
require "speedshop/cloudwatch/rack"
require "speedshop/cloudwatch/sidekiq"
require "speedshop/cloudwatch/railtie" if defined?(Rails)
