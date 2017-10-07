version = File.read(File.expand_path("../FLOW_VERSION", __dir__)).strip

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "flow-reactive_streams"
  s.version     = version
  s.summary     = ""
  s.description = ""
  s.license     = "MIT"
  s.author      = "Marc Siegel"
  s.email       = "marc@usainnov.com"
  s.homepage    = "https://github.com/ms-ati/flow"

  s.files = ["README.md"]

  s.required_ruby_version = ">= 2.3.1"

  s.add_dependency "flow-base", version
end
