# frozen_string_literal: true

namespace :db do
  desc "Test that metrics are disabled in db rake tasks"
  task test_metric_report: :environment do
    puts "Attempting to report metric from db rake task..."
    Speedshop::Cloudwatch.reporter.report("RakeTaskMetric", 1, namespace: "Test")
    puts "Metric report attempted (should be disabled)"
  end
end
