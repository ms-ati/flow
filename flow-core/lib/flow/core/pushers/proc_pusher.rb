module Flow
  module Core
    module Pushers
      class ProcPusher
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