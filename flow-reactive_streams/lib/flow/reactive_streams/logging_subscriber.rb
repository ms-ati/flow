# frozen_string_literal: true

module Flow
  module ReactiveStreams
    class LoggingSubscriber < ::ReactiveStreams::Subscriber
      def initialize(
        logger: DEFAULT_LOGGER,
        log_on_next: true,
        first_request_size: 2,
        later_requests_size: 1024
      )
        @logger = logger
        @log_on_next = log_on_next
        @first_request_size = first_request_size
        @later_requests_size = later_requests_size
      end

      def on_subscribe(subscription)
        @logger.info("#{self.class} - #on_subscribe(#{subscription})")
        @subscription = subscription
        @subscription.request(@first_request_size)
        @started = Time.now
      end

      def on_next(element)
        if @log_on_next
          @logger.info("#{self.class} - #on_next(#{element.inspect})")
        end
        @subscription.request(@later_requests_size)
      end

      def on_error(error)
        @logger.info("#{self.class} - #on_error(#{error.inspect})")
        @logger.error(error)
        log_time_taken
      end

      def on_complete
        @logger.info("#{self.class} - #on_complete")
        log_time_taken
      end

      private

      def log_time_taken
        @ended = Time.now
        duration = Time.at(@ended - @started).utc.strftime("%H:%M:%S.%L")
        @logger.info("#{self.class} - Total duration #{duration}")
      end
    end
  end
end
