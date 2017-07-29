module Flow
  module Core
    module Pushers
      class EnumerablePusher
        include DelegatingPusher

        attr_reader :enumerable

        def initialize(enumerable:)
          @enumerable = enumerable
          @pusher     = EnumeratorPusher.new(enumerator: enumerable.to_enum)
        end
      end
    end
  end
end
