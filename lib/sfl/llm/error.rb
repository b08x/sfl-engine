# frozen_string_literal: true

module SFL
  module LLM
    # Raised when Pass 2 (semantic annotation) fails for reasons other
    # than a single clause/chunk falling back to defaults — degradation
    # to Degradation.default_interpersonal/default_textual is the normal
    # path for a bad LLM response and never raises this; this is for
    # engine-level misconfiguration (e.g. no annotator/chat available).
    class Error < SFL::Error; end
  end
end
