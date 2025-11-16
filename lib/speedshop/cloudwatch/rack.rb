# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        report_queue_time(env)
        @app.call(env)
      end

      private

      def report_queue_time(env)
        header = queue_start_header(env)
        return unless header

        queue_time = calculate_queue_time(header)
        Reporter.instance.report(metric: :RequestQueueTime, value: queue_time)
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Rack metrics: #{e.message}", e)
      end

      def queue_start_header(env)
        env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"]
      end

      def calculate_queue_time(header)
        (Time.now.to_f * 1000) - header.gsub("t=", "").to_f
      end
    end
  end
end
