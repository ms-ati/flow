module ReactiveStreams
  #
  # TODO: Document Subscription
  #
  class Subscription
    # @see Reactive Streams rule 3.17
    MAX_DEMAND = (2**63) - 1

    def request(n)
      raise NotImplementedError
    end

    def cancel
      raise NotImplementedError
    end
  end
end
