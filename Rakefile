require "rspec/core/rake_task"
require "rubocop/rake_task"

PROJECT_DIRS = %i[flow-core].freeze

task default: %i[spec rubocop]

desc "Run all RSpec code examples"
task spec: PROJECT_DIRS.map { |dir| "spec:#{dir}" }

namespace :spec do
  PROJECT_DIRS.each do |dir|
    desc "Run the RSpec code examples in #{dir}"
    RSpec::Core::RakeTask.new(dir) do |t|
      t.pattern = "#{dir}/#{RSpec::Core::RakeTask::DEFAULT_PATTERN}"
    end
  end
end

RuboCop::RakeTask.new(:rubocop)
