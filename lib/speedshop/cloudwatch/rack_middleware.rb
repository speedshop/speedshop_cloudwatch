# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class RackMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          queue_start = extract_queue_start(env)

          if queue_start
            queue_time = (Time.now.to_f * 1000) - queue_start
            reporter = Speedshop::Cloudwatch.reporter
            namespace = Speedshop::Cloudwatch.config.namespaces[:rack]
            reporter.report("request_queue_time", queue_time, namespace: namespace, unit: "Milliseconds")
          end
        rescue
        end

        @app.call(env)
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
