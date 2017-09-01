require "flow/core/pusher"
require "flow/core/pusher_factory"

module Flow
  def self.pusher(arg = nil, **kw_args, &block)
    Flow::Core::PusherFactory.new.pusher(arg, **kw_args, &block)
  end
end
