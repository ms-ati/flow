# frozen_string_literal: true

begin
  require "concurrent/atomic/atomic_boolean"
rescue LoadError
  require "#{__dir__}/mutex_atomic_boolean"
end

module Flow
  module Base
    #
    # @return [Concurrent::AtomicBoolean, Flow::Base::MutexAtomicBoolean]
    #   A thread-safe and atomic boolean implementation.
    #
    # If the
    # {https://github.com/ruby-concurrency/concurrent-ruby Concurrent Ruby} gem
    # is available, uses
    # {http://www.rubydoc.info/gems/concurrent-ruby/Concurrent/AtomicBoolean its
    # implementation}, which can optimize for each Ruby platform.
    #
    # Otherwise, uses a {MutexAtomicBoolean simple mutex-based implementation}.
    #
    AtomicBoolean = if defined?(::Concurrent::AtomicBoolean) # rubocop:disable ConstantName, LineLength
                      ::Concurrent::AtomicBoolean
                    else
                      ::Flow::Base::MutexAtomicBoolean
                    end
  end
end
