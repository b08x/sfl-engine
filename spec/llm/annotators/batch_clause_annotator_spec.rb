# frozen_string_literal: true

require "spec_helper"
require "dspy"

RSpec.describe SFL::LLM::Annotators::BatchClauseAnnotator do
  subject(:annotator) { described_class.new(lm: fake_lm) }

  let(:fake_lm) { instance_double(DSPy::LM) }
  let(:fake_predictor) { instance_double(DSPy::Predict) }
  let(:fake_response) do
    double(to_h: { "annotations" => [{ "index" => 0, "mood" => "declarative" }] })
  end
  let(:contexts) do
    [
      {
        index: 0,
        text: "It works.",
        root_verb: "works",
        subjects: "It",
        clause_type: "independent",
        conjunction: nil,
      },
    ]
  end

  before do
    allow(DSPy::Predict).to receive(:new).with(SFL::LLM::Signatures::BatchClauseAnnotationSignature).and_return(fake_predictor)
    allow(fake_predictor).to receive(:configure)
  end

  it "renders every clause's context Hash into the batch prompt as numbered JSON lines" do
    allow(fake_predictor).to receive(:call).and_return(fake_response)

    annotator.call(contexts)

    expect(fake_predictor).to have_received(:call).with(
      clauses: "0: {\"index\":0,\"text\":\"It works.\",\"root_verb\":\"works\",\"subjects\":\"It\",\"clause_type\":\"independent\",\"conjunction\":null}"
    )
  end

  it "returns the symbolized annotations array" do
    allow(fake_predictor).to receive(:call).and_return(fake_response)

    expect(annotator.call(contexts)).to eq([{ index: 0, mood: "declarative" }])
  end

  describe "malformed provider responses" do
    let(:dspy_type_error) do
      TypeError.new("no implicit conversion of Float into Hash").tap do |error|
        error.set_backtrace(["/home/b08x/.rbenv/gems/dspy-0.34.0/lib/dspy/predict.rb:88:in 'call'"])
      end
    end
    let(:own_type_error) do
      TypeError.new("boom").tap do |error|
        error.set_backtrace(["/home/b08x/WorkspaceV3/sfl-engine/lib/sfl/llm/annotators/batch_clause_annotator.rb:30:in 'call'"])
      end
    end

    it "wraps a TypeError raised from dspy/predict.rb as LLM::MalformedResponse" do
      allow(fake_predictor).to receive(:call).and_raise(dspy_type_error)

      expect { annotator.call(contexts) }.to raise_error(SFL::LLM::MalformedResponse, /no implicit conversion/)
    end

    it "lets a TypeError raised from our own code keep propagating unchanged" do
      allow(fake_predictor).to receive(:call).and_raise(own_type_error)

      expect { annotator.call(contexts) }.to raise_error(TypeError, "boom")
    end
  end
end
