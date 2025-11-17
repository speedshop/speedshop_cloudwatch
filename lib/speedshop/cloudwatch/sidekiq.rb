# frozen_string_literal: true

# Portions of this code adapted from sidekiq-cloudwatchmetrics
# Copyright (c) 2018 Samuel Cochran
# https://github.com/sj26/sidekiq-cloudwatchmetrics
#
# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require "sidekiq/api" if defined?(::Sidekiq)

module Speedshop
  module Cloudwatch
    class Sidekiq
      def collect
        stats = ::Sidekiq::Stats.new
        processes = ::Sidekiq::ProcessSet.new.to_a

        report_stats(stats)
        report_utilization(processes)
        report_queue_metrics
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Sidekiq metrics: #{e.message}", e)
      end

      class << self
        def setup_lifecycle_hooks
          ::Sidekiq.configure_server do |sidekiq_config|
            if defined?(Sidekiq::Enterprise)
              sidekiq_config.on(:leader) do
                Speedshop::Cloudwatch.configure { |c| c.collectors << :sidekiq }
                Speedshop::Cloudwatch.start!
              end
            else
              sidekiq_config.on(:startup) do
                Speedshop::Cloudwatch.configure { |c| c.collectors << :sidekiq }
                Speedshop::Cloudwatch.start!
              end
            end

            sidekiq_config.on(:quiet) do
              Speedshop::Cloudwatch.stop!
            end

            sidekiq_config.on(:shutdown) do
              Speedshop::Cloudwatch.stop!
            end
          end
        end
      end

      private

      def reporter
        Speedshop::Cloudwatch.reporter
      end

      def report_stats(stats)
        {
          EnqueuedJobs: stats.enqueued, ProcessedJobs: stats.processed, FailedJobs: stats.failed,
          ScheduledJobs: stats.scheduled_size, RetryJobs: stats.retry_size, DeadJobs: stats.dead_size,
          Workers: stats.workers_size, Processes: stats.processes_size,
          DefaultQueueLatency: stats.default_queue_latency
        }.each { |m, v| reporter.report(metric: m, value: v, integration: :sidekiq) }
      end

      def report_utilization(processes)
        capacity = processes.sum { |p| p["concurrency"] }
        reporter.report(metric: :Capacity, value: capacity)

        utilization = avg_utilization(processes) * 100.0
        reporter.report(metric: :Utilization, value: utilization) unless utilization.nan?
      end

      def report_queue_metrics
        queues_to_monitor.each do |q|
          reporter.report(metric: :QueueLatency, value: q.latency, dimensions: {QueueName: q.name})
          reporter.report(metric: :QueueSize, value: q.size, dimensions: {QueueName: q.name})
        end
      end

      def queues_to_monitor
        all_queues = ::Sidekiq::Queue.all
        configured = Speedshop::Cloudwatch.config.sidekiq_queues

        if configured.nil? || configured.empty?
          all_queues
        else
          all_queues.select { |q| configured.include?(q.name) }
        end
      end

      def avg_utilization(processes)
        utils = processes.map { |p| p["busy"] / p["concurrency"].to_f }.reject(&:nan?)
        utils.sum / utils.size.to_f
      end
    end
  end
end

Speedshop::Cloudwatch::Sidekiq.setup_lifecycle_hooks
