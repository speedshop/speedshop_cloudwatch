# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Railtie < ::Rails::Railtie
      initializer "speedshop.cloudwatch.insert_middleware", before: :build_middleware_stack do |app|
        app.config.middleware.insert_before 0, Speedshop::Cloudwatch::RackMiddleware
      end

      initializer "speedshop.cloudwatch.start_reporter" do
        config.after_initialize do
          next if caller.any? { |c| c.include?("console_command.rb") || c.include?("runner_command.rb") }
          next if in_rake_task?
          Speedshop::Cloudwatch.reporter.start!
        end
      end

      def self.in_rake_task?
        return false unless defined?(::Rake) && ::Rake.respond_to?(:application)
        tasks = ::Rake.application.top_level_tasks || []
        tasks.any? { |t| t.match?(/^(assets:|db:|webpacker:)/) }
      end
    end
  end
end
