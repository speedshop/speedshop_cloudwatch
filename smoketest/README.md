# Speedshop::Cloudwatch Smoketest

Full integration test for all four gem integrations (Puma, Rack, Sidekiq, ActiveJob) using a Rails 8.0 app with WebMock to capture CloudWatch API calls. Run `./run_smoketest.sh` to start Redis, Puma (2 workers), and Sidekiq, generate traffic for 2 minutes, then verify all 22 expected metrics were captured. Requires Ruby 3.4.7 and Redis.
