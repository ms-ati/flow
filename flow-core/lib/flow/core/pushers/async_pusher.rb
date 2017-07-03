# frozen_string_literal: true

require "flow/core/pushers/delegating_pusher"

module Flow
  module Core
    module Pushers
      class AsyncPusher
        include DelegatingPusher

        attr_reader :async_start, :pusher

        def initialize(async_start:, pusher:)
          @async_start = async_start
          @pusher = pusher
        end

        def start_pushing!
          async_start.call do
            pusher.start_pushing!
          end
        end
      end
    end
  end
end
