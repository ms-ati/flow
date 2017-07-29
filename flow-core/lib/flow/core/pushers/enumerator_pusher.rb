module Flow
  module Core
    module Pushers
      class EnumeratorPusher
        include DelegatingPusher

        attr_reader :enumerator

        def initialize(enumerator:)
          @enumerator = enumerator
          @pusher     = BlockPusher.new { enumerator.next }
        end
      end
    end
  end
end
