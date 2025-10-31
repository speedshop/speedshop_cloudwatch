#!/usr/bin/env fish

set -l SMOKETEST_DIR (dirname (status --current-filename))
cd $SMOKETEST_DIR

set -x AWS_SDK_LOAD_CONFIG false
set -x AWS_CONFIG_FILE /dev/null
set -x AWS_SHARED_CREDENTIALS_FILE /dev/null

gum style --border double --padding "1 2" --border-foreground 212 "Speedshop Cloudwatch Smoketest"

echo ""
gum style --foreground 212 "Step 1: Starting Redis..."
redis-server --daemonize yes --port 6379 --pidfile tmp/redis.pid
if test $status -ne 0
    gum style --foreground 1 "❌ Failed to start Redis"
    exit 1
end
gum style --foreground 2 "✓ Redis started"

echo ""
gum style --foreground 212 "Step 2: Installing dependencies..."
bundle install --quiet
if test $status -ne 0
    gum style --foreground 1 "❌ Bundle install failed"
    redis-cli shutdown
    exit 1
end
gum style --foreground 2 "✓ Dependencies installed"

echo ""
gum style --foreground 212 "Step 3: Starting Rails server (Puma)..."
bundle exec puma -C config/puma.rb -e development > log/puma.log 2>&1 &
set -g PUMA_PID $last_pid
echo $PUMA_PID > tmp/pids/server.pid
sleep 3
if not ps -p $PUMA_PID > /dev/null
    gum style --foreground 1 "❌ Failed to start Rails server"
    redis-cli shutdown
    exit 1
end
gum style --foreground 2 "✓ Rails server started with 2 workers"

echo ""
gum style --foreground 212 "Step 4: Starting Sidekiq..."
bundle exec sidekiq > log/sidekiq.log 2>&1 &
set -g SIDEKIQ_PID $last_pid
echo $SIDEKIQ_PID > tmp/pids/sidekiq.pid
sleep 2
if not ps -p $SIDEKIQ_PID > /dev/null
    gum style --foreground 1 "❌ Failed to start Sidekiq"
    kill $PUMA_PID 2>/dev/null
    redis-cli shutdown
    exit 1
end
gum style --foreground 2 "✓ Sidekiq started"

echo ""
gum style --foreground 212 "Step 5: Generating test traffic..."

for i in (seq 1 10)
    curl -s http://localhost:3000/health > /dev/null
    curl -s -X POST http://localhost:3000/enqueue_jobs > /dev/null
    sleep 1
end

gum style --foreground 2 "✓ Generated 10 health checks and 10 job enqueues"

echo ""
gum style --foreground 212 "Step 6: Waiting for metrics collection (2 minutes)..."
gum spin --spinner dot --title "Collecting metrics..." -- sleep 120

echo ""
gum style --foreground 212 "Step 7: Stopping services..."
kill $SIDEKIQ_PID 2>/dev/null; and gum style --foreground 2 "✓ Sidekiq stopped"
kill $PUMA_PID 2>/dev/null; and gum style --foreground 2 "✓ Rails server stopped"
redis-cli shutdown; and gum style --foreground 2 "✓ Redis stopped"

sleep 2

echo ""
gum style --foreground 212 "Step 8: Verifying captured metrics..."
bundle exec ruby verify_metrics.rb

if test $status -eq 0
    echo ""
    gum style --border double --padding "1 2" --border-foreground 2 --foreground 2 "🎉 Smoketest PASSED! All metrics captured successfully."
    raycast://confetti
else
    echo ""
    gum style --border double --padding "1 2" --border-foreground 1 --foreground 1 "❌ Smoketest FAILED! See errors above."
    exit 1
end
