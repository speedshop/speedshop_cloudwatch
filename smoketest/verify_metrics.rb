require "json"
require "cgi"

EXPECTED_METRICS = {
  "Puma" => ["Workers", "BootedWorkers", "OldWorkers", "Running", "Backlog", "PoolCapacity", "MaxThreads"],
  "Rack" => ["RequestQueueTime"],
  "Sidekiq" => ["EnqueuedJobs", "ProcessedJobs", "FailedJobs", "ScheduledJobs", "RetryJobs", "DeadJobs", "Workers", "Processes", "DefaultQueueLatency", "Capacity", "Utilization", "QueueLatency", "QueueSize"],
  "ActiveJob" => ["QueueLatency"]
}

metrics_file = File.join(__dir__, "tmp", "captured_metrics.json")

unless File.exist?(metrics_file)
  puts "❌ No metrics file found at #{metrics_file}"
  exit 1
end

captured_data = JSON.parse(File.read(metrics_file))

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

puts "Summary:"
puts "  Total API calls: #{captured_data.length}"
puts "  Total unique metrics: #{captured_metrics.values.flatten.uniq.length}"
puts "  Expected metrics: #{EXPECTED_METRICS.values.flatten.length}"
puts "  Captured metrics: #{captured_metrics.values.flatten.uniq.length}"
puts ""

if all_passed
  puts "✅ All expected metrics were captured!"
  exit 0
else
  puts "❌ Missing #{missing_metrics.length} metrics:"
  missing_metrics.each { |m| puts "   - #{m}" }
  exit 1
end
