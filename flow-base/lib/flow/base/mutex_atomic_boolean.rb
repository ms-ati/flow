# frozen_string_literal: true

module Flow
  module Base
    #
    # Simple implementation of a thread-safe atomic boolean with CAS (compare
    # and set) operation, using Ruby's built-in {Mutex}. Used only if the
    # {https://github.com/ruby-concurrency/concurrent-ruby Concurrent Ruby} gem
    # is not available.
    #
    class MutexAtomicBoolean
      def initialize(initial = false)
        @value = verify_is_a_boolean(initial)
        @mutex = ::Thread::Mutex.new
      end

      def value
        @mutex.synchronize { @value }
      end

      def value=(update)
        @mutex.synchronize { @value = verify_is_a_boolean(update) }
      end

      def compare_and_set(expect, update)
        @mutex.synchronize do
          matched = (expect == @value)
          @value = verify_is_a_boolean(update) if matched
          matched
        end
      end

      def make_true
        compare_and_set(false, true)
      end

      def make_false
        compare_and_set(true, false)
      end

      private

      ALLOWED_BOOLEAN_VALUES = [true, false].freeze

      def verify_is_a_boolean(value)
        if ALLOWED_BOOLEAN_VALUES.include?(value)
          value
        else
          raise ArgumentError,
                "#{self.class.name} accepts only `true` and `false` as values."
        end
      end
    end
  end
end
