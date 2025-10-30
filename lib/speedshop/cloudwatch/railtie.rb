# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Railtie < ::Rails::Railtie
      initializer "speedshop.cloudwatch.start_reporter" do
        config.after_initialize do
          next if caller.any? { |c| c.include?("console_command.rb") || c.include?("runner_command.rb") }
          next if defined?(::Rake) && ::Rake.respond_to?(:application) && (::Rake.application.top_level_tasks || []).any? { |t| t.match?(/^(assets:|db:|webpacker:)/) }
          Speedshop::Cloudwatch.reporter.start!
        end
      end
    end
  end
end
