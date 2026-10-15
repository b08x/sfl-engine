# frozen_string_literal: true

module SFL
  module LLM
    # Raised when the provider returns a value that DSPy's predictor cannot
    # decode into the signature's output type, for example a bare number where
    # a Hash is expected. DSPy raises TypeError from dspy/predict.rb for this,
    # and LLM::Engine treats every TypeError as a programmer error, so without
    # this wrapper one bad response would crash the whole run. Not retryable:
    # the same prompt returns the same malformed value.
    #
    # Lives in its own file because Zeitwerk maps one constant to one file, and
    # error.rb autoloads only LLM::Error.
    class MalformedResponse < Error
      DSPY_PREDICT_PATH = "/dspy/predict.rb"

      # Only a TypeError whose top frame is inside DSPy's predictor is a
      # malformed response. A TypeError from our own code is a bug and must
      # keep propagating.
      # @param error [TypeError]
      # @return [Boolean]
      def self.from_predictor?(error)
        error.backtrace&.first.to_s.include?(DSPY_PREDICT_PATH)
      end
    end
  end
end
