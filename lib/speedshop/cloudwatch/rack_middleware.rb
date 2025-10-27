# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class RackMiddleware
      def initialize(app, namespace: "Rack", client: nil)
        @app = app
        @reporter = MetricReporter.new(namespace: namespace, interval: 60, client: client)
        @reporter.start!
      end

      def call(env)
        queue_start = extract_queue_start(env)

        status, headers, body = @app.call(env)

        if queue_start
          queue_time = (Time.now.to_f * 1000) - queue_start
          @reporter.report("request_queue_time", queue_time, unit: "Milliseconds")
        end

        [status, headers, body]
      end

      private

      def extract_queue_start(env)
        header = env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"]
        return nil unless header

        header.gsub("t=", "").to_f
      end
    end
  end
end
