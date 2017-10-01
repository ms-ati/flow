version = File.read(File.expand_path("../FLOW_VERSION", __dir__)).strip

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "flow-base"
  s.version     = version
  s.summary     = ""
  s.description = ""
  s.license     = "MIT"
  s.author      = "Marc Siegel"
  s.email       = "marc@usainnov.com"
  s.homepage    = "https://github.com/ms-ati/flow"

  s.files        = Dir["README.md", "CHANGELOG.md", "MIT-LICENSE", "lib/**/*"]
  s.require_path = "lib"

  s.required_ruby_version = ">= 2.3.1"
end
