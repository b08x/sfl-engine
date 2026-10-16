# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::MalformedResponse do
  def error_with(*frames)
    TypeError.new("x").tap { |error| error.set_backtrace(frames) }
  end

  describe ".from_predictor?" do
    it "matches the shape Sorbet really raises: sorbet-runtime frames on top, dspy/predict.rb beneath" do
      error = error_with(
        "/gems/sorbet-runtime-0.6.13558/lib/types/configuration.rb:261:in 'T::Configuration.call_validation_error_handler_default'",
        "/gems/sorbet-runtime-0.6.13558/lib/types/private/methods/call_validation.rb:396:in 'report_error'",
        "/gems/dspy-1.0.2/lib/dspy/predict.rb:186:in 'DSPy::Predict#forward_untyped'"
      )

      expect(described_class.from_predictor?(error)).to be(true)
    end

    it "rejects a TypeError from our own code even when sorbet-runtime frames lead it" do
      error = error_with(
        "/gems/sorbet-runtime-0.6.13558/lib/types/configuration.rb:261:in 'x'",
        "/app/lib/sfl/llm/annotators/clause_annotator.rb:30:in 'call'"
      )

      expect(described_class.from_predictor?(error)).to be(false)
    end

    it "rejects an error with no backtrace" do
      expect(described_class.from_predictor?(TypeError.new("x"))).to be(false)
    end
  end
end
