class HealthController < ApplicationController
  def index
    render json: {status: "ok", time: Time.now.to_i}
  end

  def enqueue_jobs
    TestSidekiqJob.perform_async("test-data-#{Time.now.to_i}")
    TestActiveJob.perform_later("test-data-#{Time.now.to_i}")
    render json: {status: "enqueued", time: Time.now.to_i}
  end
end
