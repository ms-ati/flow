module Flow
  module Core
    module Pushers
      class CallablePusher
        attr_reader :callable

        def initialize(callable: nil, &block)
          @callable = callable || block
        end

        def start_pushing!
          loop do
            callable.call
          end
        end
      end
    end
  end
end
