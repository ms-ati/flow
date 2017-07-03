require "flow/core/pushers/callable_pusher"
require "flow/core/pushers/delegating_pusher"

module Flow
  module Core
    module Pushers
      class BlockPusher
        include DelegatingPusher

        attr_reader :proc, :pusher

        def initialize(&block)
          @proc = block
          @pusher = CallablePusher.new(callable: @proc)
        end
      end
    end
  end
end
