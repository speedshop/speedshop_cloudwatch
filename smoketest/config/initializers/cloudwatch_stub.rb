require "webmock"
require "aws-sdk-cloudwatch"

include WebMock::API

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

$captured_metrics = []

WebMock.stub_request(:post, /monitoring\..*\.amazonaws\.com/)
  .to_return do |request|
    $captured_metrics << {
      timestamp: Time.now,
      body: request.body,
      headers: request.headers
    }

    File.write(Rails.root.join("tmp", "captured_metrics.json"), JSON.pretty_generate($captured_metrics))

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
