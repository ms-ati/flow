require "flow/base/signaller"

RSpec.describe Flow::Base::Signaller do
  context "when used in a class via composition" do
    subject(:composed) do
      c = composing_class.new
      c.mutex.lock if should_lock
      c
    end

    before :each do
      composed.foo
      composed.foo
      composed.bar(42)
    end

    let(:should_lock) { false }

    let(:composing_class) do
      Class.new do
        attr_reader :callbacks_received, :errors_seen, :signaller, :mutex

        def initialize
          @callbacks_received = Hash.new(0)

          @errors_seen = []

          @signaller = Flow::Base::Signaller.new(
            target: self,
            signals: [:foo, :bar],
            on_error: @errors_seen.method(:push)
          )

          @mutex = ::Thread::Mutex.new
        end

        def foo
          @signaller.signal(:foo)
        end

        def bar(n)
          @signaller.signal(:bar, n)
        end

        def do_foo
          @callbacks_received[:foo] += 1
        end

        def do_bar(n)
          @mutex.synchronize { @callbacks_received[:bar] += n }
        end
      end
    end

    def wait_for(secs = 3)
      raise ArgumentError, "wait_for requires a block" unless block_given?
      wait_until = Time.now + secs

      loop do
        begin
          return yield
        rescue RSpec::Expectations::ExpectationNotMetError
          raise if Time.now >= wait_until
          sleep 0.01
          next
        end
      end
    end

    context "when no lock" do
      it "processes all signals asynchronously" do
        wait_for { expect(composed.callbacks_received[:foo]).to eq(2) }
        wait_for { expect(composed.callbacks_received[:bar]).to eq(42) }
      end
    end

    context "when a mutex is locked and unlocked" do
      let(:should_lock) { true }

      it "signal processing stops and starts" do
        wait_for { expect(composed.callbacks_received[:foo]).to eq(2) }

        3.times do
          sleep 0.1
          expect(composed.callbacks_received[:bar]).to eq(0)
        end

        composed.mutex.unlock

        wait_for { expect(composed.callbacks_received[:bar]).to eq(42) }
      end
    end
  end
end
