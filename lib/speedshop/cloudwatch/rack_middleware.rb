# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class RackMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          # Header contains milliseconds since epoch (with optional "t=" prefix).
          if (header = env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"])
            queue_time = (Time.now.to_f * 1000) - header.gsub("t=", "").to_f
            Speedshop::Cloudwatch.reporter.report(RequestQueueTime: queue_time, unit: "Milliseconds")
          end
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Rack metrics: #{e.message}", e)
        end
        @app.call(env)
      end
    end
  end
end
