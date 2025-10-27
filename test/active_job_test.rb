# frozen_string_literal: true

require "test_helper"

class ActiveJobTest < Minitest::Test
  def test_active_job_module_is_defined
    assert defined?(Speedshop::Cloudwatch::ActiveJob)
  end

  def test_active_job_has_included_method
    assert_respond_to Speedshop::Cloudwatch::ActiveJob, :included
  end
end
