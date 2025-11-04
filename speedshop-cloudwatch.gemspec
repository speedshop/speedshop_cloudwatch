# frozen_string_literal: true

require_relative "lib/speedshop/cloudwatch/version"

Gem::Specification.new do |spec|
  spec.name = "speedshop-cloudwatch"
  spec.version = Speedshop::Cloudwatch::VERSION
  spec.authors = ["Nate Berkopec"]
  spec.email = ["nate.berkopec@speedshop.co"]

  spec.summary = "Ruby application integration with AWS CloudWatch for Puma, Rack, Sidekiq, and ActiveJob"
  spec.description = "This gem helps integrate your Ruby application with AWS CloudWatch, reporting metrics from Puma, Rack, Sidekiq, and ActiveJob in background threads to avoid adding latency to requests and jobs."
  spec.homepage = "https://github.com/nateberkopec/speedshop-cloudwatch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nateberkopec/speedshop-cloudwatch"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == __FILE__) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .github/ .standard.yml])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-cloudwatch", ">= 1.81.0"
end
