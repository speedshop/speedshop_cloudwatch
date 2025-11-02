require "json"
require "cgi"
require_relative "../lib/speedshop/cloudwatch/configuration"

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

captured_data.each do |request|
  params = CGI.parse(request["body"])

  namespace = params["Namespace"]&.first
  next unless namespace

  params.keys.grep(/MetricData\.member\.\d+\.MetricName/).each do |key|
    metric_name = params[key].first
    namespace_key = namespace.split("/").last
    captured_metrics[namespace_key] << metric_name unless captured_metrics[namespace_key].include?(metric_name)
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

puts "Summary:"
puts "  Total API calls: #{captured_data.length}"
puts "  Total unique metrics: #{captured_metrics.values.flatten.uniq.length}"
puts "  Expected metrics: #{EXPECTED_METRICS.values.flatten.length}"
puts "  Captured metrics: #{captured_metrics.values.flatten.uniq.length}"
puts ""

if all_passed
  puts "✅ All expected metrics were captured!"
  puts "✅ No forbidden metrics were captured!"
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
  exit 1
end
