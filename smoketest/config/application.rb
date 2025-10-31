require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module SmoketestApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.eager_load = false
    config.active_job.queue_adapter = :inline
    config.logger = Logger.new($stdout)
    config.log_level = :info
  end
end
