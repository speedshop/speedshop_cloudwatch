require "json"
require "cgi"
require_relative "../lib/speedshop/cloudwatch/config"

config = Speedshop::Cloudwatch::Config.instance

EXPECTED_METRICS = config.metrics.transform_keys { |integration|
  config.namespaces[integration]
}.transform_values { |metrics|
  metrics.map(&:to_s)
}

FORBIDDEN_METRICS = {
  "Test" => ["RakeTaskMetric"]
}

require "csv"

metrics_file = File.join(__dir__, "tmp", "captured_metrics.csv")

unless File.exist?(metrics_file)
  puts "❌ No metrics file found at #{metrics_file}"
  exit 1
end

captured_data = CSV.read(metrics_file, headers: true).map(&:to_h)

if captured_data.empty?
  puts "❌ No metrics were captured!"
  exit 1
end

puts "📊 Analyzing #{captured_data.length} CloudWatch API calls..."
puts ""

captured_metrics = Hash.new { |h, k| h[k] = [] }
metric_counts = Hash.new { |h, k| h[k] = Hash.new(0) }

captured_data.each do |request|
  params = CGI.parse(request["body"])

  namespace = params["Namespace"]&.first
  next unless namespace

  params.keys.grep(/MetricData\.member\.\d+\.MetricName/).each do |key|
    metric_name = params[key].first
    namespace_key = namespace.split("/").last
    captured_metrics[namespace_key] << metric_name unless captured_metrics[namespace_key].include?(metric_name)
    metric_counts[namespace_key][metric_name] += 1
  end
end

puts "Captured metrics by integration:"
puts ""

all_passed = true
missing_metrics = []

EXPECTED_METRICS.each do |integration, expected|
  puts "#{integration}:"
  captured = captured_metrics[integration] || []

  expected.each do |metric|
    if captured.include?(metric)
      puts "  ✓ #{metric}"
    else
      puts "  ❌ #{metric} (MISSING)"
      all_passed = false
      missing_metrics << "#{integration}/#{metric}"
    end
  end
  puts ""
end

puts "Checking for forbidden metrics (should NOT be present):"
puts ""

forbidden_found = []
FORBIDDEN_METRICS.each do |integration, forbidden|
  captured = captured_metrics[integration] || []
  forbidden.each do |metric|
    if captured.include?(metric)
      puts "  ❌ #{integration}/#{metric} (SHOULD NOT BE PRESENT)"
      forbidden_found << "#{integration}/#{metric}"
      all_passed = false
    else
      puts "  ✓ #{integration}/#{metric} correctly not captured"
    end
  end
end
puts ""

EXPECTED_METRIC_COUNTS = {
  "Rack" => {"RequestQueueTime" => 20},
  "ActiveJob" => {"QueueLatency" => 10},
  "Sidekiq" => {"EnqueuedJobs" => 1}
}

puts "Checking metric counts (based on generated traffic):"
puts ""

count_failures = []
EXPECTED_METRIC_COUNTS.each do |integration, expected_counts|
  puts "#{integration}:"
  expected_counts.each do |metric, expected_count|
    actual_count = metric_counts[integration][metric]
    if actual_count >= expected_count
      puts "  ✓ #{metric}: #{actual_count} (expected >= #{expected_count})"
    else
      puts "  ❌ #{metric}: #{actual_count} (expected >= #{expected_count})"
      count_failures << "#{integration}/#{metric}: got #{actual_count}, expected >= #{expected_count}"
      all_passed = false
    end
  end
  puts ""
end

puts "Summary:"
puts "  Total API calls: #{captured_data.length}"
puts "  Total unique metrics: #{captured_metrics.values.flatten.uniq.length}"
puts "  Expected metrics: #{EXPECTED_METRICS.values.flatten.length}"
puts "  Captured metrics: #{captured_metrics.values.flatten.uniq.length}"
puts ""

if all_passed
  puts "✅ All expected metrics were captured!"
  puts "✅ No forbidden metrics were captured!"
  puts "✅ All metric counts met expectations!"
  exit 0
else
  if missing_metrics.any?
    puts "❌ Missing #{missing_metrics.length} metrics:"
    missing_metrics.each { |m| puts "   - #{m}" }
  end
  if forbidden_found.any?
    puts "❌ Found #{forbidden_found.length} forbidden metrics:"
    forbidden_found.each { |m| puts "   - #{m}" }
  end
  if count_failures.any?
    puts "❌ #{count_failures.length} metric count assertions failed:"
    count_failures.each { |f| puts "   - #{f}" }
  end
  exit 1
end
