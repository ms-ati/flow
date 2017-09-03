# TODO: Start with project gutenberg catalog and mirror, find all bigrams

# Can we demo a reactive streams publisher of lines from `tar jtvf <file>`?

##
# 1. Spikes of reactive streams level
##

require "singleton"
require "childprocess"

class NilSubscriptionClass
  include Singleton

  def request(_); end

  def cancel; end
end

NilSubscription = NilSubscriptionClass.instance

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

##
# 2. Spikes of external process interaction with reactive streams
##

#file =
#args = ["tar", "jtvf", file]
#cp = ChildProcess.build(*args)

##
# 3. Spikes of flow dsl for building and running the above
##

require "values"

module Flow
  class Pusher
    def initialize(get_next:, for_each: [])
      @get_next = get_next
      @for_each = for_each
    end

    def each(callable = nil, &block)
      f = callable || block || (raise ArgumentError)
      self.class.new(
        get_next: @get_next,
        for_each: @for_each + [f]
      )
    end

    def go!
      loop do
        n = @get_next.call
        @for_each.each { |f| f.call(n) }
      end
    end
  end

  def self.pusher(obj = nil, **kw_args)
    case obj
    when Enumerable
      Pusher.new(get_next: obj.to_enum.method(:next))
    else
      raise ArgumentError
    end
  end

end

# First, just push the file we want to parse
files = Flow.pusher(["tmp/rdf-files.tar.bz2"])
files = files.each { |l| puts l } # lazy
puts "\nWait for it... (lazy)\n"
sleep(0.5)
puts "---\nFiles:"
files.go!

# skip downloading the file for now, add that later
# lines = Flow.
#         pusher(["tmp/rdf-files.tar.bz2"]).
#         via_process { |f| ["tar", "jtvf", f] }
#         # or
#         #via_process(->(f) { ["tar", "jtvf", f] })
#         # or
#         #via(Flow.child_process { |f| ["tar", "jtvf", f] })
#         # or
#         #into(Flow.child_process { |f| ["tar", "jtvf", f] }).puller.pusher
#
# lines.each { |l| puts l } # lazy
#
# puts "\nWait for it... (lazy)\n"
#
# puts "---\nLines:"
# lines.go!
