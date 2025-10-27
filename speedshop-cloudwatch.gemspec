# frozen_string_literal: true

require_relative "lib/speedshop/cloudwatch/version"

Gem::Specification.new do |spec|
  spec.name = "speedshop-cloudwatch"
  spec.version = Speedshop::Cloudwatch::VERSION
  spec.authors = ["Nate Berkopec"]
  spec.email = ["nate.berkopec@speedshop.co"]

  spec.summary = "TODO: Write a short summary, because RubyGems requires one."
  spec.description = "TODO: Write a longer description or delete this line."
  spec.homepage = "https://github.com/nateberkopec/speedshop-cloudwatch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nateberkopec/speedshop-cloudwatch"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-cloudwatch", ">= 1.81.0"
end
