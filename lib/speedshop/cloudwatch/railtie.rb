# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Railtie < ::Rails::Railtie
      initializer "speedshop.cloudwatch.start_reporter" do
        config.after_initialize do
          next if in_rails_console_or_runner?
          next if in_rake_task?

          Speedshop::Cloudwatch.reporter.start!
        end
      end

      private

      def in_rails_console_or_runner?
        caller.any? { |call| call.include?("console_command.rb") || call.include?("runner_command.rb") }
      end

      def in_rake_task?
        return false unless defined?(::Rake)
        return false unless ::Rake.respond_to?(:application)

        top_level_tasks = ::Rake.application.top_level_tasks || []
        top_level_tasks.any? do |task|
          task.match?(/^(assets:|db:|webpacker:)/)
        end
      end
    end
  end
end
