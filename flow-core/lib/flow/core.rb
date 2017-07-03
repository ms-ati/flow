require "flow/core/pusher"
require "flow/core/pushers/constant_pusher"

module Flow
  def pusher
    Flow::Core::Pushers::ConstantPusher.new(value: 42)
  end
  module_function :pusher
end