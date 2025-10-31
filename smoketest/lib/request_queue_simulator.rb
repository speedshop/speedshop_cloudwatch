class RequestQueueSimulator
  def initialize(app)
    @app = app
  end

  def call(env)
    unless env["HTTP_X_REQUEST_START"]
      queue_time_ms = (Time.now.to_f * 1000 - rand(10..100)).to_i
      env["HTTP_X_REQUEST_START"] = "t=#{queue_time_ms}"
    end
    @app.call(env)
  end
end
