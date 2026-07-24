# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Wraps a block with a named span for tracing/metrics (the OTel/
      # Langfuse boundary). Kept as a port, not a direct OTel dependency,
      # so core/ never requires opentelemetry-* directly.
      module Instrumenter
        # @param name [String]
        # @param payload [Hash] arbitrary attributes attached to the span
        # @yield the instrumented call
        # @return [Object] the block's return value
        def instrument(name, payload = {}, &)
          raise NotImplementedError, "#{self.class} must implement #instrument"
        end
      end
    end
  end
end
