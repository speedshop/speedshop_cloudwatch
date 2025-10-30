# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class RackMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          if (header = env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"])
            queue_time = (Time.now.to_f * 1000) - header.gsub("t=", "").to_f
            namespace = Speedshop::Cloudwatch.config.namespaces[:rack]
            Speedshop::Cloudwatch.reporter.report("RequestQueueTime", queue_time, namespace: namespace, unit: "Milliseconds")
          end
        rescue
          nil
        end
        @app.call(env)
      end
    end
  end
end
