# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    class Configuration
      attr_accessor :interval, :client

      def initialize
        @interval = 60
        @client = nil
      end
    end
  end
end
