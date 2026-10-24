# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::ReadabilityScorer do
  subject(:scorer) { described_class.new }

  it "scores word-bearing text with finite floats" do
    readability = scorer.score("The committee approved the budget.")

    expect(readability.flesch).to be_finite
    expect(readability.kincaid).to be_finite
    expect(readability.fog).to be_finite
    expect(readability.word_count).to eq(5)
  end

  # Lingua::EN::Readability computes 0.0/0 for zero-word text, yielding NaN;
  # NaN must never leave this seam (it crashes JSON.generate at the cache
  # boundary). nil is Types::Readability's "not computable" value.
  it "returns nil scores for zero-word text instead of the gem's NaN" do
    readability = scorer.score("...")

    expect(readability.flesch).to be_nil
    expect(readability.kincaid).to be_nil
    expect(readability.fog).to be_nil
    expect(readability.word_count).to eq(0)
  end
end
