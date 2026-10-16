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
      SORBET_RUNTIME_PATH = "/sorbet-runtime-"

      # Only a TypeError raised by DSPy's predictor is a malformed response.
      # Sorbet reports the failed signature check from its own frames, so the
      # top frames are sorbet-runtime and the predictor frame sits beneath
      # them; skip those and judge the first frame that is not Sorbet's. A
      # TypeError from our own code is a bug and must keep propagating.
      # @param error [TypeError]
      # @return [Boolean]
      def self.from_predictor?(error)
        frame = error.backtrace&.find { |line| !line.include?(SORBET_RUNTIME_PATH) }
        frame.to_s.include?(DSPY_PREDICT_PATH)
      end
    end
  end
end
