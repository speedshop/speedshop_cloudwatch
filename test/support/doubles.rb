# frozen_string_literal: true

module TestDoubles
  class ReporterDouble
    attr_reader :collectors, :metrics_collected

    def initialize
      @collectors = []
      @metrics_collected = []
    end

    def report(metric_name, value, **options)
      @metrics_collected << {name: metric_name, value: value, **options}
    end

    def register_collector(integration, &block)
      @collectors << {integration: integration, block: block}
    end
  end

  class QueueDouble
    attr_reader :name, :size, :latency

    def initialize(name, size, latency)
      @name = name
      @size = size
      @latency = latency
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

  class SidekiqConfigDouble
    attr_reader :callbacks

    def initialize
      @callbacks = {}
    end

    def on(event, &block)
      @callbacks[event] = block
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
