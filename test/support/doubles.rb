# frozen_string_literal: true

module TestDoubles
  class LoggerDouble
    attr_reader :errors, :debugs, :infos

    def initialize
      @errors = []
      @debugs = []
      @infos = []
    end

    def error(msg)
      @errors << msg
    end

    def debug(msg)
      @debugs << msg
    end

    def info(msg)
      @infos << msg
    end

    def error_logged?(pattern)
      @errors.any? { |msg| msg.include?(pattern) }
    end
  end

  class RailsDouble
    attr_reader :application

    def initialize
      @application = ApplicationDouble.new
    end

    def respond_to?(method)
      method == :application
    end
  end

  class ApplicationDouble
    attr_reader :middleware

    def initialize
      @middleware = MiddlewareDouble.new
    end
  end

  class MiddlewareDouble
    attr_reader :inserted

    def initialize
      @inserted = []
    end

    def insert_after(after_middleware, new_middleware)
      @inserted << {after: after_middleware, middleware: new_middleware}
    end
  end

  class RakeDouble
    attr_reader :application

    def initialize(top_level_tasks)
      @application = Struct.new(:top_level_tasks).new(top_level_tasks)
    end

    def respond_to?(method)
      method == :application
    end
  end
end
