require "rspec/core/rake_task"
require "rubocop/rake_task"

SUB_PROJECTS = %i[base core].freeze
PROJECT_DIRS = SUB_PROJECTS.map { |p| "flow-#{p}".to_sym }

task default: %i[spec rubocop]

desc "Run all RSpec code examples"
task spec: PROJECT_DIRS.map { |dir| "spec:#{dir}" }

namespace :spec do
  PROJECT_DIRS.each do |dir|
    desc "Run the RSpec code examples in #{dir}"
    RSpec::Core::RakeTask.new(dir) do |t|
      t.ruby_opts = "-I#{dir}/lib"
      t.pattern = "#{dir}/#{RSpec::Core::RakeTask::DEFAULT_PATTERN}"
    end
  end
end

RuboCop::RakeTask.new(:rubocop)
