RSpec.describe "Flow::Base::AtomicBoolean" do
  subject do
    load_scoped_to_test_module!
    test_module::Flow::Base::AtomicBoolean
  end

  def load_scoped_to_test_module!
    f = "#{__dir__}/../../../lib/flow/base/atomic_boolean.rb"
    test_module.module_eval(File.read(f), f)
  end

  let(:test_module) do
    m = Module.new
    allow(m).to receive(:require).and_call_original
    m
  end

  context "when 'concurrent-ruby' is *not* available" do
    before :each do
      hide_const("Concurrent::AtomicBoolean")

      allow(test_module).
        to receive(:require).
        with("concurrent/atomic/atomic_boolean").
        and_raise(LoadError)
    end

    it { is_expected.to be(Flow::Base::MutexAtomicBoolean) }
  end

  context "when 'concurrent-ruby' *is* available" do
    before :each do
      allow(test_module).
        to receive(:require).
        with("concurrent/atomic/atomic_boolean") do
          stub_const("Concurrent::AtomicBoolean", expected_value)
        end
    end

    let(:expected_value) { "Concurrent::AtomicBoolean" }

    it { is_expected.to be(expected_value) }
  end
end
