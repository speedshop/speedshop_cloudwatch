class TestActiveJob < ApplicationJob
  queue_as :default

  def perform(data)
    Rails.logger.info "TestActiveJob processing: #{data}"
    sleep 0.1
  end
end
