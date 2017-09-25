# TODO: Start with project gutenberg catalog and mirror, find all bigrams

# Can we demo a reactive streams publisher of lines from `tar jtvf <file>`?

##
# 1. Spikes of reactive streams level
##

require "childprocess"
require "values"

module ReactiveStreams
  module API
    class Publisher
      def subscribe(subscriber)
        raise NotImplementedError
      end
    end

    class Subscriber
      def on_subscribe(subscription)
        raise NotImplementedError
      end

      def on_next(element)
        raise NotImplementedError
      end

      def on_error(error)
        raise NotImplementedError
      end

      def on_complete
        raise NotImplementedError
      end
    end

    class Subscription
      # @see Reactive Streams rule 3.17, but use the max Fixnum on MRI
      MAX_DEMAND = (2**62) - 1

      def request(n)
        raise NotImplementedError
      end

      def cancel
        raise NotImplementedError
      end
    end
  end

  module Tools
    class NilSubscriberClass < ReactiveStreams::API::Subscriber
      private_class_method :new
      def on_subscribe(_); end
      def on_next(_); end
      def on_error(_); end
      def on_complete; end
    end

    NIL_SUBSCRIBER = NilSubscriberClass.send(:new)

    class NilSubscriptionClass < ReactiveStreams::API::Subscription
      private_class_method :new
      def request(_); end
      def cancel(_); end
    end

    NIL_SUBSCRIPTION = NilSubscriptionClass.send(:new)

    DEFAULT_LOGGER = begin
      l = Logger.new($stderr)
      l.level = Logger::INFO
      l
    end

    class LoggingSubscriber < ReactiveStreams::API::Subscriber
      def initialize(
        logger: DEFAULT_LOGGER,
        first_request_size: 1024,
        later_requests_size: 1024
      )
        @logger = logger
        @first_request_size = first_request_size
        @later_requests_size = later_requests_size
      end

      def on_subscribe(subscription)
        @logger.info("#{self.class} - #on_subscribe(#{subscription})")
        @subscription = subscription
        @subscription.request(@first_request_size)
      end

      def on_next(element)
        @logger.info("#{self.class} - #on_next(#{element.inspect})")
        @subscription.request(@later_requests_size)
      end

      def on_error(error)
        @logger.info("#{self.class} - #on_error(#{error.inspect})")
        @logger.error(error)
      end

      def on_complete
        @logger.info("#{self.class} - #on_complete")
      end
    end

    class PumpingPublisher < ReactiveStreams::API::Publisher
      DEFAULT_SCHEDULE = Thread.method(:new)
      DEFAULT_BATCH_SIZE = 1024

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

      class PumpingSubscription < ReactiveStreams::API::Subscription
        attr_reader :subscriber

        # @param logger [Logger]
        def initialize(subscriber:, get_next:, schedule:, batch_size:, logger:)
          @subscriber = subscriber
          @get_next = get_next
          @schedule = schedule
          @batch_size = batch_size
          @logger = logger

          @cancelled = false
          @demand = 0

          @pending_signals = Queue.new
        end

        def start
          signal(:start)
        end

        def request(n)
          signal(:request, n)
        end

        def cancel
          signal(:cancel)
        end

        private

        def signal(s, n = nil)
          @pending_signals << (n ? [s, n] : s)
          try_to_schedule
        end

        def try_to_schedule
          @running ||= @schedule.call(&self.method(:run))
        end

        def run
          loop do
            s, n = begin
                     @pending_signals.pop(true)
                   rescue ThreadError
                     # For some reason, ThreadError means empty queue here
                     break
                   end

            # If cancelled, just keep emptying the pending signals queue
            next if @cancelled

            case s
            when :start
              do_start
            when :request
              do_request(n)
            when :send
              do_send
            when :cancel
              do_cancel
            else
              m = "PumpingSubscription unrecognized signal: #{s.inspect}"
              terminate_due_to(ReactiveStreamsError.new(m))
            end
          end

          @running = nil
        end

        def do_start
          @subscriber.on_subscribe(self)
        rescue StandardError => error
          terminate_due_to(error)
        end

        def do_request(n)
          if n < 1
            m = "Subscriber violated the Reactive Streams rule 3.9 by "\
                "requesting a non-positive number of elements. Subscriber: "\
                "#{subscriber.inspect}."
            terminate_due_to(ReactiveStreamsError.new(m))
          else
            @demand = @demand > (MAX_DEMAND - n) ? MAX_DEMAND : @demand + n
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
            rescue StopIteration
              # If we are at End-of-Stream, we need to consider this
              # `Subscription` as cancelled as per rule 1.6. Then we signal
              # `on_complete` as per rule 1.2 and 1.5.
              do_cancel
              @subscriber.on_complete
            rescue StandardError => error
              # If `get_next` raises (it can, since it is user-provided), we
              # need to treat it as publisher error as per rule 1.4
              terminate_due_to(error)
            end

            # Then we signal the next element downstream to the `Subscriber`
            @subscriber.on_next(next_element) unless @cancelled

            # Keep going until exhausted batch or demand, or cancelled
            left_in_batch -= 1
            @demand -= 1
            break if @cancelled || left_in_batch.zero? || @demand.zero?
          end

          # If the `Subscription` is still alive and well, and we have demand to
          # satisfy, we signal ourselves to be scheduled to send more data.
          signal(:send) if !@cancelled && @demand > 0

        rescue StandardError => error
          # We can only get here if `on_next` or `on_complete` raised, and they
          # are not allowed to according to rule 2.13, so we can only cancel and
          # log here.
          do_cancel

          m = "Subscriber violated the Reactive Streams rule 2.13 by raising "\
              "an exception from on_next or on_complete. Subscriber: "\
              "#{@subscriber.inspect}."
          @logger.error(ReactiveStreamsError.new(m))
          @logger.error(error)
        end

        # Handles cancellation requests, and is idempotent, thread-safe and not
        # synchronously performing heavy computations as specified in rule 3.5
        def do_cancel
          @cancelled = true
        end

        def terminate_due_to(error)
          # When we signal on_error, the subscription must be considered as
          # cancelled, as per rule 1.6
          do_cancel

          # Then we signal the error downstream, to the `Subscriber`
          @subscriber.on_error(error)

        rescue StandardError => error2
          # If `on_error` throws an exception, this is a spec violation
          # according to rule 1.9 and 2.13, and all we can do is to log it.
          m = "Subscriber#on_error violated the Reactive Streams rule 2.13 "\
              "by raising an exception. Subscriber: #{@subscriber.inspect}."
          @logger.error(ReactiveStreamsError.new(m))
          @logger.error(error2)
        end
      end
    end

    class IOPublisher < ReactiveStreams::Tools::PumpingPublisher
      def initialize(input_io:, **args)
        super(get_next: input_io.each_line.method(:next), **args)
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

class ChildProcessPublisher < ReactiveStreams::Tools::IOPublisher
  def initialize(process:, **args)
    @process = process

    verify_process_not_started
    setup_finalizer
    setup_pipe

    super(input_io: @input_io, **args)
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

# require "./gutenberg_bigrams.rb"

## Demo basic "pumping" reactive streams publisher into logging subscriber
def demo_basic_pumping
  n = 0
  g = -> { n += 1; raise StopIteration if n > 1000; n }
  p = ReactiveStreams::Tools::PumpingPublisher.new(get_next: g)
  s = ReactiveStreams::Tools::LoggingSubscriber.new
  p.subscribe(s)
  [p, s]
end

## Demo IO-reading reactive streams publisher into logging subscriber
def demo_pump_read_io
  io = File.open("./gutenberg_bigrams.rb", "r")
  p = ReactiveStreams::Tools::IOPublisher.new(input_io: io)
  s = ReactiveStreams::Tools::LoggingSubscriber.new
  p.subscribe(s)
  [p, s]
end

## Demo process pipe-reading reactive streams publisher into logging subscriber
def demo_pump_child_process_pipe
  f = File.join(__dir__, "..", "..", "tmp", "rdf-files.tar.bz2")
  cp = ChildProcess.build("tar", "jtvf", f)
  p = ChildProcessPublisher.new(process: cp)
  s = ReactiveStreams::Tools::LoggingSubscriber.new
  p.subscribe(s)
  [p, s]
end
