class ApplicationJob < ActiveJob::Base
  include Speedshop::Cloudwatch::ActiveJob
end
