# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::DerivationHash do
  let(:premise) { SFL::Core::Types::Premise.new(type: "pos", source: "works", value: "VERB", weight: 0.5) }

  describe ".compute" do
    it "is deterministic for the same inputs" do
      args = { premises: [premise], inference_rule: "rule_a", conclusion: { mood: "declarative" } }

      first_call = described_class.compute(**args)
      second_call = described_class.compute(**args)

      expect(first_call).to eq(second_call)
    end

    it "changes when the conclusion changes" do
      a = described_class.compute(premises: [premise], inference_rule: "rule_a", conclusion: { mood: "declarative" })
      b = described_class.compute(premises: [premise], inference_rule: "rule_a", conclusion: { mood: "imperative" })

      expect(a).not_to eq(b)
    end

    it "produces identical output for symbol-keyed and string-keyed conclusions" do
      symbol_keyed = described_class.compute(premises: [premise], inference_rule: "r", conclusion: { mood: "x" })
      string_keyed = described_class.compute(premises: [premise], inference_rule: "r", conclusion: { "mood" => "x" })

      expect(symbol_keyed).to eq(string_keyed)
    end

    it "produces identical output for Types::Premise instances and equivalent plain Hashes" do
      struct_form = described_class.compute(premises: [premise], inference_rule: "r", conclusion: {})
      hash_form = described_class.compute(
        premises: [{ type: "pos", source: "works", value: "VERB", weight: 0.5 }],
        inference_rule: "r", conclusion: {}
      )

      expect(struct_form).to eq(hash_form)
    end

    it "is insensitive to premise order (sorted internally)" do
      premise_b = SFL::Core::Types::Premise.new(type: "dep", source: "nsubj", value: "It", weight: nil)

      forward = described_class.compute(premises: [premise, premise_b], inference_rule: "r", conclusion: {})
      reversed = described_class.compute(premises: [premise_b, premise], inference_rule: "r", conclusion: {})

      expect(forward).to eq(reversed)
    end

    it "returns a 64-character hex SHA256 digest" do
      hash = described_class.compute(premises: [], inference_rule: "r", conclusion: {})

      expect(hash).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
