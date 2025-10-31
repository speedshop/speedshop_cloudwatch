#!/usr/bin/env bash

SMOKETEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SMOKETEST_DIR"

export AWS_SDK_LOAD_CONFIG=false
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null

gum style --border double --padding "1 2" --border-foreground 212 "Speedshop Cloudwatch Smoketest"

echo ""
gum style --foreground 212 "Step 1: Starting Redis..."
redis-server --daemonize yes --port 6379 --pidfile tmp/redis.pid
if [ $? -ne 0 ]; then
    gum style --foreground 1 "❌ Failed to start Redis"
    exit 1
fi
gum style --foreground 2 "✓ Redis started"

echo ""
gum style --foreground 212 "Step 2: Installing dependencies..."
mise exec -- bundle install --quiet
if [ $? -ne 0 ]; then
    gum style --foreground 1 "❌ Bundle install failed"
    redis-cli shutdown
    exit 1
fi
gum style --foreground 2 "✓ Dependencies installed"

echo ""
gum style --foreground 212 "Step 3: Starting Rails server (Puma)..."
mise exec -- bundle exec puma -C config/puma.rb -e development > log/puma.log 2>&1 &
PUMA_PID=$!
echo $PUMA_PID > tmp/pids/server.pid
sleep 3
if ! ps -p $PUMA_PID > /dev/null; then
    gum style --foreground 1 "❌ Failed to start Rails server"
    redis-cli shutdown
    exit 1
fi
gum style --foreground 2 "✓ Rails server started with 2 workers"

echo ""
gum style --foreground 212 "Step 4: Starting Sidekiq..."
mise exec -- bundle exec sidekiq > log/sidekiq.log 2>&1 &
SIDEKIQ_PID=$!
echo $SIDEKIQ_PID > tmp/pids/sidekiq.pid
sleep 2
if ! ps -p $SIDEKIQ_PID > /dev/null; then
    gum style --foreground 1 "❌ Failed to start Sidekiq"
    cat log/sidekiq.log
    kill $PUMA_PID 2>/dev/null
    redis-cli shutdown
    exit 1
fi
gum style --foreground 2 "✓ Sidekiq started"

echo ""
gum style --foreground 212 "Step 5: Generating test traffic..."

for i in {1..10}; do
    curl -s http://localhost:3000/health > /dev/null
    curl -s -X POST http://localhost:3000/enqueue_jobs > /dev/null
    sleep 1
done

gum style --foreground 2 "✓ Generated 10 health checks and 10 job enqueues"

echo ""
gum style --foreground 212 "Step 6: Waiting for metrics collection (2 minutes)..."
gum spin --spinner dot --title "Collecting metrics..." -- sleep 120

echo ""
gum style --foreground 212 "Step 7: Stopping services..."
kill $SIDEKIQ_PID 2>/dev/null && gum style --foreground 2 "✓ Sidekiq stopped"
kill $PUMA_PID 2>/dev/null && gum style --foreground 2 "✓ Rails server stopped"
redis-cli shutdown && gum style --foreground 2 "✓ Redis stopped"

sleep 2

echo ""
gum style --foreground 212 "Step 8: Verifying captured metrics..."
mise exec -- bundle exec ruby verify_metrics.rb

if [ $? -eq 0 ]; then
    echo ""
    gum style --border double --padding "1 2" --border-foreground 2 --foreground 2 "🎉 Smoketest PASSED! All metrics captured successfully."
    open "raycast://confetti" 2>/dev/null || true
else
    echo ""
    gum style --border double --padding "1 2" --border-foreground 1 --foreground 1 "❌ Smoketest FAILED! See errors above."
    exit 1
fi
