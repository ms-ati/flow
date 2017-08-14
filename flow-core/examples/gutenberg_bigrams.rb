# TODO: Start with project gutenberg catalog and mirror, find all bigrams

# Can we demo a reactive streams publisher of lines from `tar jtvf <file>`?

require "childprocess"

class ChildProcessPublisher
  attr_reader :process

  def initialize(process)
    @process = process
    verify_initial_state
    setup_pipe
    #setup_finalizer
  end

  def subscribe

  private

  def setup_pipe
    @read_io, w = IO.pipe
    process.io.stdout = w
    process.io.stderr = $stderr
  end

  def verify_initial_state
    raise ArgumentError, "Invalid ChildProcess: #{process.inspect}" if
      process.nil? || process.send(:started?)
  end
end

file = "tmp/rdf-files.tar.bz2"
args = ["tar", "jtvf", file]
cp = ChildProcess.build(*args)
