# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Narrators::NarrativeGenerator do
  let(:lm) { instance_double(DSPy::LM) }
  let(:predictor) { instance_double(DSPy::Predict, configure: nil) }
  let(:chain_of_thought) { instance_double(DSPy::ChainOfThought, configure: nil) }

  before do
    allow(DSPy::Predict).to receive(:new).and_return(predictor)
    allow(DSPy::ChainOfThought).to receive(:new).and_return(chain_of_thought)
  end

  it "uses DSPy::Predict for V0, the one-line baseline" do
    described_class.new(lm:, variant: :v0)

    expect(DSPy::Predict).to have_received(:new).with(SFL::LLM::Signatures::NarrativeSignatureV0)
    expect(DSPy::ChainOfThought).not_to have_received(:new)
  end

  it "uses DSPy::ChainOfThought for V1" do
    described_class.new(lm:, variant: :v1)

    expect(DSPy::ChainOfThought).to have_received(:new).with(SFL::LLM::Signatures::NarrativeSignatureV1)
  end

  it "uses DSPy::ChainOfThought for V2" do
    described_class.new(lm:, variant: :v2)

    expect(DSPy::ChainOfThought).to have_received(:new).with(SFL::LLM::Signatures::NarrativeSignatureV2)
  end

  it "defaults to V1" do
    described_class.new(lm:)

    expect(DSPy::ChainOfThought).to have_received(:new).with(SFL::LLM::Signatures::NarrativeSignatureV1)
  end

  it "rejects an unknown variant rather than falling back silently" do
    expect { described_class.new(lm:, variant: :v9) }.to raise_error(ArgumentError, /unknown narrative variant/)
  end
end
