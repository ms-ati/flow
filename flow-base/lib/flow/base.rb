# frozen_string_literal: true

require "flow/base/signaller"

module Flow
  DEFAULT_LOGGER = begin
    l = Logger.new($stderr)
    l.level = Logger::INFO
    l
  end
end
