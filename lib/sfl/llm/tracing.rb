# frozen_string_literal: true

require "dspy/o11y/langfuse"

module SFL
  module LLM
    # Explicit tracing configuration wrapper, replacing the legacy approach
    # of implicit require-time ENV reads. Called by SFL::Boot at call time.
    module Tracing
      module_function def configure(host:, public_key:, secret_key:)
        # The dspy-o11y-langfuse gem currently still reads from ENV natively
        # under the hood, so we ensure the explicit arguments are placed where
        # it expects them before triggering the observability configuration.
        ENV["LANGFUSE_HOST"] = host
        ENV["LANGFUSE_PUBLIC_KEY"] = public_key
        ENV["LANGFUSE_SECRET_KEY"] = secret_key

        DSPy::Observability.configure!(adapter: :langfuse)
      end
    end
  end
end
