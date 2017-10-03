# frozen_string_literal: true

require "flow/base/atomic_boolean"
require "flow/errors"

module Flow
  module Base
    #
    # TODO: Document Signaller class
    #
    class Signaller
      #
      # @param signals [Array<Symbol, Hash{Symbol => Proc}>]
      #   Names of signals to handle, assuming a convention that the target's
      #   signal handler functions are the prefix "do_" followed by the signal
      #   name. For exceptions to this rule, just provide a Hash mapping signal
      #   names to their callbacks.
      #
      # @param target [Object]
      #   Target object to receive asynchronous signal handler callbacks as the
      #   pending signals queue is processed. Generally also the submitter of
      #   pending signals. Required if *any* signals are provided by name,
      #   rather than as a map from symbol to proc callback.
      #
      # @param num_per_run [Integer]
      #   How many signals the main loop will process in one run before
      #   rescheduling itself to run again.
      #
      # @param runner [Runner]
      #   How we'll run the signaller's main loop (usually asynchronously).
      #
      def initialize(
        signals:,
        target:,
        runner:      RUN_IN_NEW_THREAD,
        num_per_run: 2,
        on_error:    Logger.new($stderr).method(:error)
      )
        # Error handling is solely via `on_error`
        @on_error = on_error

        # Signals and their mapping to callbacks (usually methods on the target)
        @callbacks_by_signal = setup_callbacks(signals, target)

        # Configure how we'll run the signaller's main loop
        @runner = runner
        @num_per_run = num_per_run

        # Only one signaler main loop can run at a time
        @is_running = AtomicBoolean.new
        @is_cancelled = AtomicBoolean.new
        @pending_signals = Queue.new
        @main_loop = method(:main_loop).to_proc
      end

      #
      # Add a signal to the queue, to be processed asynchronously.
      #
      # @param name [Symbol]
      #   Name of the signal to process
      #
      # @param args [Array]
      #   Optional arguments to be passed to the signal's callback
      #
      def signal(name, *args)
        @pending_signals << (args.empty? ? name : [name, args])
        try_to_run_main_loop
      end

      #
      # Cancel this signal processing queue.
      #
      # Usually called from inside a signal callback method on the `target`,
      # since usually the target wants to complete its own clean-up in
      # addition to stopping the signal-processing loop.
      #
      def cancel
        @is_cancelled.value = true
      end

      private

      # By default, signal names are prefixed to find callback methods on target
      CALLBACK_PREFIX = "do_"

      # An instance of an anonymous class, to compare equal only to itself
      NO_PENDING_SIGNALS = Class.new.new.freeze

      # The main signal processing loop
      def main_loop
        # Establishes a happens-before relationship with end of previous run
        return unless @is_running.value

        num_left = @num_per_run

        loop do
          next_signal, args = next_pending_signal
          call_signal_callback(next_signal, args)

          break if (num_left -= 1).zero? || NO_PENDING_SIGNALS == next_signal
        end
      rescue StandardError => error
        terminate_due_to(error)
      ensure
        # Establishes a happens-before relationship with beginning of next run
        @is_running.value = false

        # If we still have signals to process, schedule ourselves to run again
        try_to_run_main_loop unless @pending_signals.empty?
      end

      # @return [NO_PENDING_SIGNALS, Symbol, Array(Symbol, Array)]
      #   Return the next pending signal (optionally with arguments) in the
      #   queue, or a special value indicating there are no pending signals.
      #
      def next_pending_signal
        @pending_signals.pop(true)
      rescue ThreadError # Indicates that the queue is empty
        NO_PENDING_SIGNALS
      end

      def call_signal_callback(next_signal, args)
        return if @is_cancelled || NO_PENDING_SIGNALS == next_signal

        signal_callback = @callbacks_by_signal[next_signal] || begin
          msg = "#{self.class.name} received an unrecognized signal: "\
                "#{next_signal.inspect}"
          raise Flow::Error, msg
        end

        signal_callback.call(*args)
      end

      def try_to_run_main_loop
        # Only schedule to run if not already running
        @runner.call(&@main_loop) if @is_running.make_true
      rescue StandardError => error
        # If we can't schedule to run, we need to fail gracefully
        terminate_due_to(error)
      end

      def terminate_due_to(error)
        cancel
        @on_error.call(error)
      end

      # @param signals [Array<Symbol, Hash{Symbol => Proc}>]
      # @param target [Object]
      # @return [Hash{Symbol => Proc}]
      def setup_callbacks(signals, target)
        signals.inject({}) do |hsh, sym_or_hsh|
          hsh.merge(callback_mapping_for(sym_or_hsh, target))
        end.freeze
      end

      # @param sym_or_hsh [Symbol, Hash{Symbol => Proc}]
      # @param target [Object]
      # @return [Hash{Symbol => Proc}]
      def callback_mapping_for(sym_or_hsh, target)
        if sym_or_hsh.is_a? Symbol
          callback = target.method("#{CALLBACK_PREFIX}#{sym_or_hsh}".to_sym)
          { sym_or_hsh => callback }
        else
          sym_or_hsh
        end
      end
    end
  end
end
