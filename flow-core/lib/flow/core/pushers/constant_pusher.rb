require "flow/core/pushers/delegating_pusher"
require "flow/core/pushers/block_pusher"

module Flow
  module Core
    module Pushers
      class ConstantPusher
        include DelegatingPusher

        attr_reader :constant

        def initialize(constant:)
          @constant = constant
          @pusher = BlockPusher.new { constant }
        end
      end
    end
  end
end