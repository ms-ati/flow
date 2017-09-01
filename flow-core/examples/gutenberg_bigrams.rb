# TODO: Start with project gutenberg catalog and mirror, find all bigrams

# Can we demo a reactive streams publisher of lines from `tar jtvf <file>`?

require "singleton"
require "childprocess"

class NilSubscription
  include Singleton

  def request(_); end

  def cancel; end
end

class PublisherStateError < StandardError; end

class ChildProcessPublisher

  def initialize(process)
    @process = process
    @subscriber = nil
    check_process_not_started
    setup_finalizer
    setup_pipe
  end

  def subscribe(subscriber)
    if @subscriber.nil?
      @subscriber = subscriber
      @subscriber.on_subscribe(Subscription.new(self))
    else
      subscriber.on_subscribe(NilSubscription.instance)
      subscriber.on_error(PublisherStateError.new())
    end

  end

  private

  def check_process_not_started
    raise ArgumentError, "Invalid ChildProcess: #{@process.inspect}" if
      @process.nil? || @process.send(:started?)
  end

  def check_no_subscriber
    raise
  end

  def setup_finalizer
    ObjectSpace.define_finalizer(self, Finalizer.new(@process))
  end

  def setup_pipe
    @read_io, @process.io.stdout = IO.pipe
    @process.io.stderr = $stderr
  end

  # @see ObjectSpace#define_finalizer
  class Finalizer
    def initialize(process)
      @process = process
    end

    def call(*)
      @process&.stop(1)
    end
  end
end

file = "tmp/rdf-files.tar.bz2"
args = ["tar", "jtvf", file]
cp = ChildProcess.build(*args)
