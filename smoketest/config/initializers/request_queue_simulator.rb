require_relative "../../lib/request_queue_simulator"

Rails.application.config.middleware.insert_before 0, RequestQueueSimulator
