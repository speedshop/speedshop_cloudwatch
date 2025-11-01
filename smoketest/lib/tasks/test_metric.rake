# frozen_string_literal: true

namespace :db do
  desc "Test that metrics are disabled in db rake tasks"
  task test_metric_report: :environment do
    puts "Attempting to report metric from db rake task..."
    Speedshop::Cloudwatch.reporter.report(metric: "RakeTaskMetric", value: 1, namespace: "Test")
  end
end
