class TestSidekiqJob
  include Sidekiq::Job

  def perform(data)
    Rails.logger.info "TestSidekiqJob processing: #{data}"
    sleep 0.1
  end
end
