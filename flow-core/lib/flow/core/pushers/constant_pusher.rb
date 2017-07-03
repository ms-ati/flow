require "flow/core/pushers/delegating_pusher"
require "flow/core/pushers/proc_pusher"

module Flow
  module Core
    module Pushers
      class ConstantPusher
        include DelegatingPusher

        attr_reader :value

        def initialize(value:)
          @value = value
          @pusher = ProcPusher.new { value }
        end
      end
    end
  end
end