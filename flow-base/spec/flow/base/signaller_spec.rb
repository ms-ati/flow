require "flow/base/signaller"

RSpec.describe Flow::Base::Signaller do
  context "when used in a class via composition" do
    subject(:composed) do
      composing_class.new
    end

    before :each do
      composed.foo
      composed.foo
      composed.bar(42)
    end

    let(:composing_class) do
      Class.new do
        attr_reader :callbacks_received, :errors_seen, :signaller, :mutex

        def initialize
          @callbacks_received = {}

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
          @callbacks_received[:bar] += n
        end
      end
    end

    context "when no locks" do
      it "does all callbacks" do
        wait_for { composed.callbacks_received[:foo] }.to eq(2)
        wait_for { composed.callbacks_received[:bar] }.to eq(42)
      end
    end
  end
end
