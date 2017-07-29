module Flow
  module Core
    module Pushers
      module DelegatingPusher
        attr_reader :pusher

        def start_pushing!
          pusher.start_pushing!
        end
      end
    end
  end
end
