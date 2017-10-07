# TODO: Start with project gutenberg catalog and mirror, find all bigrams

# Can we demo a reactive streams publisher of lines from `tar jtvf <file>`?

##
# 1. Spikes of reactive streams level
##
require "childprocess"
require "flow/reactive_streams"

module ReactiveStreams
  module Tools
    class NilSubscriberClass < ReactiveStreams::Subscriber
      private_class_method :new
      def on_subscribe(_); end
      def on_next(_); end
      def on_error(_); end
      def on_complete; end
    end

    NIL_SUBSCRIBER = NilSubscriberClass.send(:new)

    class NilSubscriptionClass < ReactiveStreams::Subscription
      private_class_method :new
      def request(_); end
      def cancel(_); end
    end

    NIL_SUBSCRIPTION = NilSubscriptionClass.send(:new)

    class LoggingSubscriber < ReactiveStreams::Subscriber
      def initialize(
        logger: DEFAULT_LOGGER,
        log_on_next: true,
        first_request_size: 2,
        later_requests_size: 1024
      )
        @logger = logger
        @log_on_next = log_on_next
        @first_request_size = first_request_size
        @later_requests_size = later_requests_size
      end

      def on_subscribe(subscription)
        @logger.info("#{self.class} - #on_subscribe(#{subscription})")
        @subscription = subscription
        @subscription.request(@first_request_size)
        @started = Time.now
      end

      def on_next(element)
        if @log_on_next
          @logger.info("#{self.class} - #on_next(#{element.inspect})")
        end
        @subscription.request(@later_requests_size)
      end

      def on_error(error)
        @logger.info("#{self.class} - #on_error(#{error.inspect})")
        @logger.error(error)
        log_time_taken
      end

      def on_complete
        @logger.info("#{self.class} - #on_complete")
        log_time_taken
      end

      private

      def log_time_taken
        @ended = Time.now
        duration = Time.at(@ended - @started).utc.strftime("%H:%M:%S.%L")
        @logger.info("#{self.class} - Total duration #{duration}")
      end
    end

    DEFAULT_LOGGER = begin
      l = Logger.new($stderr)
      l.level = Logger::INFO
      l
    end

    class Runner
      def call(&block)
        raise NotImplementedError
      end
    end

    # TODO: Move all this out or away
    RUN_IN_NEW_THREAD = Thread.method(:new)
    RUN_IN_NEW_FIBER = ->(&block) { Fiber.new(&block).resume }

    class IOWaiter
      def call(io, for_read: true, for_write: false, &callback)
        raise NotImplementedError
      end
    end

    class IOSelector < IOWaiter
    end

    DEFAULT_SCHEDULE = Thread.method(:new)

    DEFAULT_BATCH_SIZE = 1024

    class PumpingPublisher < ReactiveStreams::Publisher
      def initialize(
        get_next:,
        only_one:   true,
        schedule:   DEFAULT_SCHEDULE,
        batch_size: DEFAULT_BATCH_SIZE,
        logger:     DEFAULT_LOGGER
      )
        @get_next = get_next
        @only_one = only_one
        @schedule = schedule
        @batch_size = batch_size
        @logger = logger
        @subscriptions = []
      end

      def subscribe(subscriber)
        return unless verify_different(subscriber) &&
                      verify_only_one(subscriber)

        subscription = PumpingSubscription.new(
          subscriber: subscriber,
          get_next: @get_next,
          schedule: @schedule,
          batch_size: @batch_size,
          logger: @logger
        )

        subscription.start # constructor finishes before concurrency starts

        @subscriptions << subscription
      end

      private

      # @see https://github.com/reactive-streams/reactive-streams-jvm/tree/v1.0.1#1.10
      def verify_different(subscriber)
        verify(
          that: @subscriptions.find { |s| s.subscriber == subscriber }.nil?,
          msg: "Publisher#subscribe called > 1 time with: #{subscriber}",
          subscriber: subscriber
        )
      end

      def verify_only_one(subscriber)
        verify(
          that: !@only_one || @subscriptions.empty?,
          msg: "#{self.class}#subscribe called > 1 time with only_one: true",
          subscriber: subscriber
        )
      end

      def verify(that:, msg:, subscriber:)
        subscriber.on_error(ReactiveStreamsError.new(msg)) unless that
        that
      end

      class PumpingSubscription < ReactiveStreams::Subscription
        attr_reader :subscriber

        # @param logger [Logger]
        def initialize(subscriber:, get_next:, schedule:, batch_size:, logger:)
          @subscriber = subscriber
          @get_next = get_next
          @batch_size = batch_size
          @logger = logger

          @signaller = Flow::Base::Signaller.new(
            signals:  [:start, :request],
            target:   self,
            runner:   schedule,
            on_error: subscriber.method(:on_error),
          )

          @demand = 0
        end

        def start
          @signaller.signal(:start)
        end

        def request(n)
          @signaller.signal(:request, n)
        end

        def cancel
          @signaller.cancel
        end

        def cancelled?
          @signaller.cancelled?
        end

        private

        def do_start
          @subscriber.on_subscribe(self)
        end

        def do_request(n)
          if n < 1
            msg = "Subscriber violated the Reactive Streams rule 3.9 by "\
                  "requesting a non-positive number of elements. Subscriber: "\
                  "#{subscriber.inspect}."
            raise ReactiveStreamsError, msg
          else
            @demand = [@demand + n, MAX_DEMAND].min
            do_send
          end
        end

        def do_send
          # In order to not monopolize the cpu we will only send at-most
          # `batch_size` before rescheduling ourselves.
          left_in_batch = @batch_size

          loop do
            begin
              # First we pump the user-provided function for the next element
              next_element = @get_next.call

            rescue StopIteration, EOFError
              # If we are at End-of-Stream, we need to consider this
              # `Subscription` as cancelled as per rule 1.6. Then we signal
              # `on_complete` as per rule 1.2 and 1.5.
              cancel
              @subscriber.on_complete
            end

            # Then we signal the next element downstream to the `Subscriber`
            @subscriber.on_next(next_element) unless cancelled?

            # Keep going until exhausted batch or demand, or cancelled
            left_in_batch -= 1
            @demand -= 1
            break if cancelled? || left_in_batch.zero? || @demand.zero?
          end

          # If the `Subscription` is still alive and well, and we have demand to
          # satisfy, we signal ourselves to be scheduled to send more data.
          signal(:send) if !cancelled? && @demand > 0

        rescue StandardError => error
          # We can only get here if '#on_next' or '#on_complete' raised, and
          # they are not allowed to according to rule 2.13, so we can only
          # cancel and log here.
          subscriber_raised(error: error, in_method: [:on_next, :on_complete])
        end

        # Handle subscriber raising exceptions which violate Reactive Streams
        # rule 2.13. All we can do is cancel and log them.
        def subscriber_raised(error:, in_method:)
          cancel

          method_names = [*in_method].map { |sym| "'##{sym}'" }.join(" or ")

          msg = "Subscriber violated the Reactive Streams rule 2.13 by "\
                "raising an exception in #{method_names}. "\
                "Subscriber: #{@subscriber.inspect}."

          @logger.error(ReactiveStreamsError.new(msg))
          @logger.error(error)
        end
      end
    end

    class QueuingSubscriber < ReactiveStreams::Subscriber
      def initialize
        @pending_signals = Queue.new
      end
    end

    class IOPublisher < ReactiveStreams::Tools::PumpingPublisher
      def initialize(input_io:, **args)
        # Fails due to Fiber across Threads:
        # super(get_next: input_io.each_line.method(:next), **args)
        super(get_next: input_io.method(:readline), **args)
      end
    end

    class ReactiveStreamsError < StandardError; end
  end
end

<<~SKETCH_OF_KV_PROTOCOL
    / == ROOT_PREFIX

    Processors behave as a Publisher and a Subscriber that share the same id.

    id == identifier of an *instance* of the streaming step. Can be anything, an
          opaque string

    MAY include optional 'config' node to capture differences from convention,
    such as `{ serialization: "msgpack" }`, where default is "json".

    Reactive Streams Key-Value Driver Interface (TODO)

    ==============================================================================

    /publishers/id/status <-- { state: "running", heartbeat_at: "2017-09-16T20:04:03.898974Z" }
    /publishers/id/subscribe/id <-- filename is subscriber id, content anything

    /subscribers/id/status
    /subscribers/id/on_subscribe/id <-- filename is subscription id, content anything
    /subscribers/id/on_next/0
    /subscribers/id/on_next/1-5 <-- items 1-5 inclusive
    /subscribers/id/on_next/6
    /subscribers/id/on_error/0 <-- { publisher_id: "id", time: "", error: "" }
    /subscribers/id/on_complete <-- only presence matters

    /subscriptions/id/publisher_id
    /subscriptions/id/subscriber_id
    /subscriptions/id/status
    /subscriptions/id/request/0 <-- 3     // only content is the `n` value
    /subscriptions/id/request/1 <-- 1024
    /subscriptions/id/cancel <-- only presence matters

SKETCH_OF_KV_PROTOCOL

# module ReactiveStreams
#   module KV
#     module API
#       class Driver
#         def with_root_prefix(root_prefix)
#           raise NotImplementedError
#         end
#
#         def keys(prefix)
#           raise NotImplementedError
#         end
#
#         def fetch_io(key)
#           raise NotImplementedError
#         end
#       end
#     end
#
#     module Drivers
#       class FileDriver < ReactiveStreams::KV::Driver
#
#       end
#     end
#
#     module Tools
#       DEFAULT_ROOT_PREFIX = "streams"
#       DEFAULT_DRIVER = Drivers::FileDriver.new(root_prefix: DEFAULT_ROOT_PREFIX)
#
#     end
#   end
# end

class ChildProcessPublisher < ReactiveStreams::Tools::PumpingPublisher
  def initialize(process:, **args)
    @process = process

    verify_process_not_started
    setup_finalizer
    setup_pipe

    super(get_next: self.method(:readline_and_raise_if_dead), **args)
  end

  def subscribe(subscriber)
    super(subscriber)
    start_process
  end

  private

  def verify_process_not_started
    raise ArgumentError, "Invalid ChildProcess: #{@process.inspect}" if
      @process.nil? || @process.send(:started?)
  end

  def setup_finalizer
    ObjectSpace.define_finalizer(self, Finalizer.new(@process))
  end

  def setup_pipe
    @input_io, @process.io.stdout = IO.pipe
    @process.io.stderr = $stderr
  end

  def start_process
    @process.start
    @process.io.stdout.close
  end

  def readline_and_raise_if_dead
    @input_io.readline
  rescue EOFError
    if @process.crashed?
      msg = "Process died with exit code: #{@process.exit_code}. "\
            "Process: #{@process.inspect}"
      raise msg
    else
      raise
    end
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
# 3. Spikes of flow dsl for building and running the above
##

module Flow
  class Pusher
    def initialize(get_next:, for_each: [])
      @get_next = get_next
      @for_each = for_each
    end

    def each(callable = nil, &block)
      f = callable || block || (raise ArgumentError, "Needs block or callable")
      self.class.new(
        get_next: @get_next,
        for_each: @for_each + [f]
      )
    end

    def go!

      # loop do
      #   n = @get_next.call
      #   @for_each.each { |f| f.call(n) }
      # end
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

# First, just push the file(s) we want to parse
# files = Flow.pusher(["tmp/rdf-files.tar.bz2"])
# files = files.each { |l| puts l } # lazy
# puts "\nWait for it... (lazy)\n"
# sleep(0.5)
# puts "---\nFiles:"
# files.go!

# Nouns of the flow dsl:
#   - Puller: Pulls elements synchronously
#   - Pusher: Pushes elements asynchronously
#   - Target: Receives from Pusher, can be pulled from

# Second, create one process per file to parse
# processes = Flow.
#             pusher(["tmp/rdf-files.tar.bz2"])

# Third, represent output of process(es) as flow
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

Thread.abort_on_exception = true

def demo_of(
  publisher:,
  subscriber: ReactiveStreams::Tools::LoggingSubscriber.new(log_on_next: false)
)
  publisher.subscribe(subscriber)
  @prevent_gc_of = [publisher, subscriber]
end

## Demo basic "pumping" reactive streams publisher into logging subscriber
def demo_pump_basic
  # Fails due to Fiber across Threads:
  #g = (0...1000).to_enum.method(:next)
  n = 0
  g = -> { n += 1; raise StopIteration if n > 1000; n }
  demo_of(publisher: ReactiveStreams::Tools::PumpingPublisher.new(get_next: g))
end

## Demo scheduling using a Fiber to allow support for Ruby Enumerators
def demo_pump_fiber
  g = (0...10000).to_enum.method(:next)
  s = ->(&block) { Fiber.new(&block).resume }
  demo_of(publisher: ReactiveStreams::Tools::PumpingPublisher.new(get_next: g, schedule: s))
end

## Demo IO-reading reactive streams publisher into logging subscriber
def demo_pump_io
  io = File.open("./gutenberg_bigrams.rb", "r")
  demo_of(publisher: ReactiveStreams::Tools::IOPublisher.new(input_io: io))
end

## Demo process pipe-reading reactive streams publisher into logging subscriber
def demo_pump_process
  f = File.join(__dir__, "..", "..", "tmp", "rdf-files.tar.bz2")
  cp = ChildProcess.build("tar", "-tjvf", f)
  demo_of(publisher: ChildProcessPublisher.new(process: cp))
end

#
# To interact in console:
#
#   bundle exec irb -r ./gutenberg_bigrams.rb
#
#
# To non-interactively run a demo:
#
#   bundle exec ruby -e 'require "./gutenberg_bigrams.rb"; demo_pump_process; gets'
#
