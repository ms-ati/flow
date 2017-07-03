module Flow
  module Core
    module Pushers
      class EnumerablePusher
        include DelegatingPusher

        attr_reader :enumerable

        def initialize(enumerable:)
          @enumerable = enumerable
          @pusher = ProcPusher.new { value }
        end
      end
    end
  end
end