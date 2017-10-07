module ReactiveStreams
  #
  # TODO: Document Subscriber
  #
  class Subscriber
    def on_subscribe(subscription)
      raise NotImplementedError
    end

    def on_next(element)
      raise NotImplementedError
    end

    def on_error(error)
      raise NotImplementedError
    end

    def on_complete
      raise NotImplementedError
    end
  end
end
