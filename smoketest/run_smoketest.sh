#!/usr/bin/env bash

set -e

SMOKETEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SMOKETEST_DIR"

export AWS_SDK_LOAD_CONFIG=false
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null

echo "========================================"
echo "  Speedshop Cloudwatch Smoketest"
echo "========================================"
echo ""

echo "Step 1: Starting Redis..."
redis-server --daemonize yes --port 6379 --pidfile tmp/redis.pid
echo "✓ Redis started"
echo ""

echo "Step 2: Installing dependencies..."
bundle install --quiet
echo "✓ Dependencies installed"
echo ""

echo "Step 3: Starting Rails server (Puma)..."
mkdir -p log tmp/pids
bundle exec puma -C config/puma.rb -e development > log/puma.log 2>&1 &
PUMA_PID=$!
echo $PUMA_PID > tmp/pids/server.pid
sleep 3
if ! ps -p $PUMA_PID > /dev/null; then
    echo "❌ Failed to start Rails server"
    cat log/puma.log
    redis-cli shutdown
    exit 1
fi
echo "✓ Rails server started with 2 workers"
echo ""

echo "Step 4: Starting Sidekiq..."
bundle exec sidekiq > log/sidekiq.log 2>&1 &
SIDEKIQ_PID=$!
echo $SIDEKIQ_PID > tmp/pids/sidekiq.pid
sleep 2
if ! ps -p $SIDEKIQ_PID > /dev/null; then
    echo "❌ Failed to start Sidekiq"
    cat log/sidekiq.log
    kill $PUMA_PID 2>/dev/null
    redis-cli shutdown
    exit 1
fi
echo "✓ Sidekiq started"
echo ""

echo "Step 5: Generating test traffic..."
for i in {1..10}; do
    curl -s http://localhost:3000/health > /dev/null
    curl -s -X POST http://localhost:3000/enqueue_jobs > /dev/null
    sleep 1
done
echo "✓ Generated 10 health checks and 10 job enqueues"
echo ""

echo "Step 6: Testing db rake task (should not report metrics)..."
bundle exec rake db:test_metric_report
echo "✓ Rake task completed"
echo ""

echo "Step 7: Waiting for metrics collection (2 minutes)..."
sleep 120
echo "✓ Metrics collected"
echo ""

echo "Step 8: Stopping services..."
kill $SIDEKIQ_PID 2>/dev/null && echo "✓ Sidekiq stopped"
kill $PUMA_PID 2>/dev/null && echo "✓ Rails server stopped"
redis-cli shutdown && echo "✓ Redis stopped"
sleep 2
echo ""

echo "Step 9: Verifying captured metrics..."
bundle exec ruby verify_metrics.rb

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "  🎉 Smoketest PASSED!"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo "  ❌ Smoketest FAILED!"
    echo "========================================"
    exit 1
fi
