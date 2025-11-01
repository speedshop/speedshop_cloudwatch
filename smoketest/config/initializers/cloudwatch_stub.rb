require "aws-sdk-cloudwatch"
require "csv"
require "webmock"

include WebMock::API

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

METRICS_FILE = Rails.root.join("tmp", "captured_metrics.csv")

FileUtils.mkdir_p(Rails.root.join("tmp"))

CSV.open(METRICS_FILE, "w") do |csv|
  csv << ["timestamp", "body", "headers"]
end

WebMock.stub_request(:post, /monitoring\..*\.amazonaws\.com/)
  .to_return do |request|
    CSV.open(METRICS_FILE, "a") do |csv|
      csv << [Time.now.to_s, request.body, request.headers.to_json]
    end

    {status: 200, body: '<?xml version="1.0"?><PutMetricDataResponse xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/"><ResponseMetadata><RequestId>test-request-id</RequestId></ResponseMetadata></PutMetricDataResponse>'}
  end

Speedshop::Cloudwatch.configure do |config|
  config.client = Aws::CloudWatch::Client.new(
    region: "us-east-1",
    credentials: Aws::Credentials.new("fake-key", "fake-secret")
  )
  config.interval = 15
  config.logger = Rails.logger
end
