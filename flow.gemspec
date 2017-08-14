version = File.read(File.expand_path("FLOW_VERSION", __dir__)).strip

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "flow"
  s.version     = version
  s.summary     = "Asynchronous push/pull flows in Ruby."
  s.description = "Flow is a library for programming using asynchronous"\
                  "push/pull flows in Ruby. It shares some of the same design"\
                  "goals as ReactiveX, while aiming for a very narrow set of"\
                  "well-defined abstractions."
  s.license     = "MIT"
  s.author      = "Marc Siegel"
  s.email       = "marc@usainnov.com"
  s.homepage    = "https://github.com/ms-ati/flow"

  s.files = ["README.md"]

  s.required_ruby_version = ">= 2.3.1"

  s.add_dependency "flow-core", version
  # s.add_dependency "flow-even", version
  # s.add_dependency "flow-over", version

  s.add_dependency "childprocess", "~> 0.7"
end
