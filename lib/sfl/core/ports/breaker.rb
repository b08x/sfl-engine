# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Wraps a single call (typically an LLM annotation request) with one
      # owned timeout and failure-counting policy. "Single timeout
      # ownership" means only the Breaker sets a deadline for the call it
      # wraps — callers and callees must not layer their own competing
      # timeouts around the same request.
      module Breaker
        # @param label [String] identifies the call site for metrics/logs
        # @yield the guarded call
        # @return [Object] the block's return value
        # @raise [SFL::Core::Ports::Breaker::OpenError] if the breaker is open
        def call(label, &)
          raise NotImplementedError, "#{self.class} must implement #call"
        end

        # Raised when the breaker is open and refuses to attempt the call.
        class OpenError < StandardError; end
      end
    end
  end
end
