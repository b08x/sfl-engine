# frozen_string_literal: true

require "spec_helper"
require_relative "../../fixtures/narrative/compiler_narrative_signature"

RSpec.describe SFL::LLM::Signatures do
  def field_descriptions(signature)
    signature.output_json_schema.fetch(:properties).transform_values { |schema| schema[:description] }
  end

  describe SFL::LLM::Signatures::NarrativeSignatureV1 do
    let(:compiler) { SflCompilerFixture::NarrativeSignature }

    it "carries sfl-compiler's description verbatim" do
      expect(described_class.description).to eq(compiler.description)
    end

    it "carries sfl-compiler's output field descriptions verbatim" do
      expect(field_descriptions(described_class)).to eq(field_descriptions(compiler))
    end

    it "carries sfl-compiler's input field description verbatim" do
      expect(described_class.input_json_schema.dig(:properties, :digest, :description))
        .to eq(compiler.input_json_schema.dig(:properties, :analysis_digest, :description))
    end
  end

  describe SFL::LLM::Signatures::NarrativeSignatureV0 do
    it "keeps the original one-line description as the baseline" do
      expect(described_class.description).to eq("Generate a synthesized narrative from the provided analysis digest.")
    end

    it "keeps the original six output fields" do
      expect(field_descriptions(described_class).keys)
        .to contain_exactly(:overview, :cast_and_roles, :interpersonal_dynamics, :conversational_arc,
          :data_quality, :takeaways)
    end
  end

  describe SFL::LLM::Signatures::NarrativeSignatureV2 do
    it "starts from V1's description, so the compiler's rules still apply" do
      expect(described_class.description).to start_with(SFL::LLM::Signatures::NarrativeSignatureV1.description)
    end

    it "adds the grounding rules: turn citations, exact numbers and hedging" do
      expect(described_class.description).to include("turn N", "exact", "hedge")
    end

    it "keeps V1's output fields" do
      expect(field_descriptions(described_class)).to eq(field_descriptions(SFL::LLM::Signatures::NarrativeSignatureV1))
    end
  end
end
