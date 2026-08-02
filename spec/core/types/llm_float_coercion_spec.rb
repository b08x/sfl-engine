# frozen_string_literal: true

require "spec_helper"

# Regression coverage for a live-data bug (2026-08-02): ruby_llm-schema
# sometimes serializes a boundary confidence/weight value (0 or 1) as a bare
# JSON integer rather than 0.0/1.0. Every one of these four attributes used
# to be strict Types::Float, so a single boundary value anywhere in a Pass 2
# response discarded the *entire* clause's annotation (100% of clauses
# defaulted in the live run that surfaced this) — the same failure shape
# Premise#type's own comment already documents for a different field.
# rubocop:disable RSpec/DescribeClass -- cross-cutting behavior spanning four
# distinct classes/constants (ModalityWeight, TenorValue, Premise, ReasoningTrace),
# not one class's own spec file.
RSpec.describe "LLM-facing Float attributes accept a bare Integer (coerced, not rejected)" do
  it "SFL::Core::Types::ModalityWeight coerces an Integer boundary value" do
    expect(SFL::Core::Types::ModalityWeight[0]).to eq(0.0)
    expect(SFL::Core::Types::ModalityWeight[1]).to eq(1.0)
  end

  it "SFL::Core::Types::TenorValue coerces an Integer boundary value" do
    expect(SFL::Core::Types::TenorValue[0]).to eq(0.0)
    expect(SFL::Core::Types::TenorValue[1]).to eq(1.0)
  end

  it "Premise#weight coerces an Integer and still accepts nil" do
    premise = SFL::Core::Types::Premise.new(type: "pos_tag", source: "spacy", value: "VBD", weight: 1)

    expect(premise.weight).to eq(1.0)
    expect(SFL::Core::Types::Premise.new(type: "t", source: "s", value: "v", weight: nil).weight).to be_nil
  end

  it "ReasoningTrace#confidence coerces an Integer boundary value" do
    trace = SFL::Core::Types::ReasoningTrace.new(
      premises: [], inference_rule: "rule", conclusion: {}, confidence: 1,
      derivation_hash: "abc", generated_at: Time.now
    )

    expect(trace.confidence).to eq(1.0)
  end

  it "InterpersonalPayload builds successfully end-to-end with Integer modality_weight/tenor, " \
    "the exact shape that discarded 100% of clauses in the live run this fixes" do
    payload = SFL::Core::Types::InterpersonalPayload.new(
      clause_id: "c-1", mood: "declarative", modality_weight: 0, tenor: 1,
      speaker_attitude: "neutral", reasoning: "x", annotation_source: "llm",
      reasoning_trace: SFL::Core::Types::ReasoningTrace.new(
        premises: [SFL::Core::Types::Premise.new(type: "t", source: "s", value: "v", weight: 1)],
        inference_rule: "rule", conclusion: {}, confidence: 0,
        derivation_hash: "abc", generated_at: Time.now
      )
    )

    expect(payload.modality_weight).to eq(0.0)
    expect(payload.tenor).to eq(1.0)
    expect(payload.reasoning_trace.confidence).to eq(0.0)
    expect(payload.reasoning_trace.premises.first.weight).to eq(1.0)
  end
end
# rubocop:enable RSpec/DescribeClass
