# frozen_string_literal: true

require "timeout"

module SFL
  module Core
    module Ports
      # Minimal Breaker adapter: owns exactly one Timeout.timeout around
      # the wrapped call and nothing else — no failure counting, no
      # trip/open state. "Single timeout ownership" (track decision 7)
      # means this is the *only* timeout allowed around a guarded call;
      # a caller or callee layering its own competing timeout on top
      # defeats the point of centralizing it here.
      #
      # Deliberately not a full circuit breaker: there is no historical
      # failure count and therefore no OpenError to raise from this
      # adapter — Timeout::Error propagates as-is. A trip/open variant
      # can be added later as a second adapter if that behavior is
      # actually needed, rather than speculatively built in now.
      class TimeoutBreaker
        include Ports::Breaker

        def initialize(timeout_seconds:)
          @timeout_seconds = timeout_seconds
        end

        # @param label [String] used only in the Timeout::Error message
        # @yield the guarded call
        # @return [Object] the block's return value
        def call(label, &)
          return yield if @timeout_seconds.nil? || @timeout_seconds.zero?

          Timeout.timeout(@timeout_seconds, Timeout::Error, "#{label} exceeded #{@timeout_seconds}s timeout", &)
        end
      end
    end
  end
end
