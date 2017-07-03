# frozen_string_literal: true

require "set"
require "flow/core/pushers/block_pusher"
require "flow/core/pushers/callable_pusher"
require "flow/core/pushers/constant_pusher"

module Flow
  module Core
    class PusherFactory
      CLASSES_BY_OPTIONS = {
        block:    Pushers::BlockPusher,
        callable: Pushers::CallablePusher,
        constant: Pushers::ConstantPusher
      }.freeze

      DEFAULT_OPTIONS = CLASSES_BY_OPTIONS.map { |k, _| [k, nil] }.to_h.merge(
        start_async: Thread.method(:new)
      ).freeze

      EXCLUSIVE_OPTIONS = Set.new(CLASSES_BY_OPTIONS.keys).freeze

      def pusher(**kw_args, &block)
        options = DEFAULT_OPTIONS.merge(kw_args)
        options[:block] = block if block_given?
        ensure_valid(options)
        create_pusher(options)
      end

      private

      def create_pusher(options)
        opt = exclusive_options_provided(options).first
        klass = CLASSES_BY_OPTIONS[opt]
        non_exclusives = options.reject do |k, _|
          k == :block || k != opt && EXCLUSIVE_OPTIONS.include?(k)
        end
        klass.new(**non_exclusives, &options[:block])
      end

      def ensure_valid(options)
        ensure_all_known(options)
        ensure_exactly_one_exclusive(options)
      end

      def ensure_all_known(options)
        unknowns = options.keys.reject { |o| DEFAULT_OPTIONS.key?(o) }
        return if unknowns.empty?
        raise ArgumentError, "Unknown options: #{unknowns.inspect}"
      end

      def ensure_exactly_one_exclusive(options)
        exclusives = exclusive_options_provided(options)
        return if exclusives.size <= 1
        raise ArgumentError, "Required exactly one of: "\
                             "#{EXCLUSIVE_OPTIONS.inspect}, but received: "\
                             "#{exclusives.inspect}"
      end

      def exclusive_options_provided(options)
        options.select { |o, _| EXCLUSIVE_OPTIONS.include?(o) }.compact.keys
      end
    end
  end
end
