require "core/pusher"
require "core/pushers/constant_pusher"

module Flow
  def pusher
    Flow::Core::Pushers::ConstantPusher.new(value: 42)
  end
end