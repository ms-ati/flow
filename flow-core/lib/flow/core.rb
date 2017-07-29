require "flow/core/pusher"
require "flow/core/pusher_factory"

module Flow
  def self.pusher(**kw_args, &block)
    Flow::Core::PusherFactory.new.pusher(**kw_args, &block)
  end
end
