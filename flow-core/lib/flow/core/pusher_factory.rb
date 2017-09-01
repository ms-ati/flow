# frozen_string_literal: true

require "set"
require "flow/core/pushers/async_pusher"
require "flow/core/pushers/block_pusher"
require "flow/core/pushers/callable_pusher"
require "flow/core/pushers/constant_pusher"
require "flow/core/pushers/enumerable_pusher"
require "flow/core/pushers/enumerator_pusher"

module Flow
  module Core
    class PusherFactory
      ASYNC_START_METHODS = {
        new_thread: Thread.method(:new)
      }.freeze

      CATCH = nil # what was I doing here?

      CLASSES_BY_OPTIONS = {
        block:      Pushers::BlockPusher,
        callable:   Pushers::CallablePusher,
        constant:   Pushers::ConstantPusher,
        enumerable: Pushers::EnumerablePusher,
        enumerator: Pushers::EnumeratorPusher
      }.freeze

      DEFAULT_OPTIONS = CLASSES_BY_OPTIONS.map { |k, _| [k, nil] }.to_h.merge(
        async_start: :new_thread

      ).freeze

      EXCLUSIVE_OPTIONS = Set.new(CLASSES_BY_OPTIONS.keys).freeze

      def pusher(arg = nil, **kw_args, &block)
        options = parse_args(arg, kw_args, block)
        ensure_valid(options)
        create_pusher(options)
      end

      private

      def parse_args(arg, kw_args, block)
        DEFAULT_OPTIONS.
          merge(arg.nil? ? {} : parse_non_keyword(arg)).
          merge(kw_args).
          merge(block.nil? ? {} : { block: block })
      end

      def parse_non_keyword(arg)
        case arg
        when Enumerable
          { enumerable: arg }
        else
          raise ArgumentError,
                "Unrecognized non-keyword argument: #{arg.inspect}"
        end
      end

      def create_pusher(options)
        klass = pusher_class_for(options)
        block, async_start, kw_args = prepare_pusher_args(options)
        pusher = klass.new(**kw_args, &block)

        if async_start
          async_call = ASYNC_START_METHODS[async_start] || async_start
          Pushers::AsyncPusher.new(async_start: async_call, pusher: pusher)
        else
          pusher
        end
      end

      def pusher_class_for(options)
        opt = exclusive_options_provided(options).first
        CLASSES_BY_OPTIONS[opt]
      end

      def prepare_pusher_args(options)
        opts = options.dup
        block = opts.delete(:block)
        async_start = opts.delete(:async_start)
        opts.reject! { |_, v| v.nil? }
        [block, async_start, opts]
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
        require "pp"
        return if exclusives.size == 1
        raise ArgumentError,
              "Must provide a keyword argument. Allowed values are: "\
              "#{EXCLUSIVE_OPTIONS.map(&:to_s).join(', ')}"
      end

      def exclusive_options_provided(options)
        options
          .select { |k, _| EXCLUSIVE_OPTIONS.include?(k) }
          .reject { |_, v| v.nil? }
          .keys
      end
    end
  end
end
