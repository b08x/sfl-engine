# frozen_string_literal: true

module SFL
  module Boot
    # Raised for any Boot-time misconfiguration: a required provider API
    # key missing from ENV, an unreachable/cancelled Langfuse tracing
    # endpoint, or a failed database connection. Boot's own error class
    # rather than reusing LLM::Error — these failures aren't specific to
    # LLM::Engine's use case (LLM::Error's own comment scopes it to Pass 2
    # engine-level misconfiguration), and Boot is the composition root for
    # the whole app, not just the LLM layer (it also owns DB connection
    # and tracing preflight, neither of which is an LLM concern).
    class Error < SFL::Error; end
  end
end
