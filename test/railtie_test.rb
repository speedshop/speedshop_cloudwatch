# frozen_string_literal: true

require "test_helper"

begin
  require "rails"
rescue LoadError
  return
end

require "speedshop/cloudwatch/railtie"

class RailtieTest < Minitest::Test
  def setup
    @railtie = Speedshop::Cloudwatch::Railtie.new
  end

  def test_railtie_is_defined
    assert defined?(Speedshop::Cloudwatch::Railtie)
  end

  def test_railtie_inherits_from_rails_railtie
    assert Speedshop::Cloudwatch::Railtie < Rails::Railtie
  end

  def test_in_rails_console_or_runner_detects_console
    call_stack = ["lib/rails/commands/console_command.rb:123"]
    @railtie.stub :caller, call_stack do
      assert @railtie.send(:in_rails_console_or_runner?)
    end
  end

  def test_in_rails_console_or_runner_detects_runner
    call_stack = ["lib/rails/commands/runner_command.rb:123"]
    @railtie.stub :caller, call_stack do
      assert @railtie.send(:in_rails_console_or_runner?)
    end
  end

  def test_in_rails_console_or_runner_returns_false_for_normal_boot
    call_stack = ["lib/rails/application.rb:123"]
    @railtie.stub :caller, call_stack do
      refute @railtie.send(:in_rails_console_or_runner?)
    end
  end

  def test_in_rake_task_returns_false_when_rake_not_defined
    Object.stub_const(:Rake, nil) do
      refute @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_returns_false_when_no_application
    rake_double = Class.new do
      def self.respond_to?(method)
        false
      end
    end

    Object.stub_const(:Rake, rake_double) do
      refute @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_detects_asset_tasks
    rake_double = build_rake_double(["assets:precompile"])
    Object.stub_const(:Rake, rake_double) do
      assert @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_detects_db_tasks
    rake_double = build_rake_double(["db:migrate"])
    Object.stub_const(:Rake, rake_double) do
      assert @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_detects_webpacker_tasks
    rake_double = build_rake_double(["webpacker:compile"])
    Object.stub_const(:Rake, rake_double) do
      assert @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_returns_false_for_other_tasks
    rake_double = build_rake_double(["custom:task"])
    Object.stub_const(:Rake, rake_double) do
      refute @railtie.send(:in_rake_task?)
    end
  end

  def test_in_rake_task_handles_nil_top_level_tasks
    rake_double = build_rake_double(nil)
    Object.stub_const(:Rake, rake_double) do
      refute @railtie.send(:in_rake_task?)
    end
  end

  private

  def build_rake_double(tasks)
    app_double = Struct.new(:top_level_tasks).new(tasks)
    Class.new do
      define_singleton_method(:respond_to?) { |method| method == :application }
      define_singleton_method(:application) { app_double }
    end
  end
end
