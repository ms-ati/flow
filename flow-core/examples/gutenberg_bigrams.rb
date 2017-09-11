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

    class PumpingPublisher < ReactiveStreams::API::Publisher
      DEFAULT_SCHEDULE = Thread.method(:new)
      DEFAULT_BATCH_SIZE = 1024

      def initialize(
        get_next:,
        only_one: true,
        schedule: DEFAULT_SCHEDULE,
        batch_size: DEFAULT_BATCH_SIZE
      )
        @get_next = get_next
        @only_one = only_one
        @schedule = schedule
        @batch_size = batch_size
        @subscriptions = []
      end

      def subscribe(subscriber)
        ensure_different(subscriber)
        ensure_only_one(subscriber) if @only_one
        subscription = PumpingSubscription.
                       new(subscriber, @get_next, @schedule, @batch_size)
        subscription.start # constructor finishes before concurrency starts
        @subscriptions << subscription
      end

      private

      # @see https://github.com/reactive-streams/reactive-streams-jvm/tree/v1.0.1#1.10
      def ensure_different(subscriber)
        unless @subscriptions.find { |s| s.subscriber == subscriber }.nil?
          m = "Publisher#subscribe called > 1 time with: #{subscriber.inspect}"
          subscriber.on_error(ReactiveStreamsError.new(m))
        end
      end

      def ensure_only_one(subscriber)
        unless @subscriptions.empty?
          m = "#{self.class.to_s}#subscribe called > 1 time with only_one: true"
          subscriber.on_error(ReactiveStreamsError.new(m))
        end
      end

      class PumpingSubscription < ReactiveStreams::API::Subscription
        def initialize(subscriber, get_next, schedule, batch_size)
          @subscriber = subscriber
          @get_next = get_next
          @schedule = schedule
          @batch_size = batch_size

          @cancelled = false
          @demand = 0

          @pending_signals = Queue.new
        end

        def start
          signal(:subscribe)
        end

        def request(n)
          signal(:request, n)
        end

        def cancel
          signal(:cancel)
        end

        private

        def signal(s, args = nil)
          @pending_signals << (args ? { s => args } : s)
          try_to_schedule
        end

        def try_to_schedule
          @running ||= @schedule.call(&self.method(:run))
        end

        def run
          s = @pending_signals.pop(true) rescue nil

          case s
          when :subscribe
            do_subscribe
          when Hash
            do_request(s[:request])
          when :cancel
            # TODO
          end

          @running = nil
        end
      end
    end

    class ReactiveStreamsError < StandardError; end
  end
end




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
files = Flow.pusher(["tmp/rdf-files.tar.bz2"])
files = files.each { |l| puts l } # lazy
puts "\nWait for it... (lazy)\n"
sleep(0.5)
puts "---\nFiles:"
files.go!

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
