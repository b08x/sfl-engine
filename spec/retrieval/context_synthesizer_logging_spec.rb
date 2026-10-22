# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Retrieval::ContextSynthesizer, "#synthesize logging" do
  it "logs invalid synthesizer output as a warn with query and error_message fields" do
    row = SFL::Core::Types::RetrievalResult.new(
      clause_id: "c1", text: "t", section_id: "d1", rrf_score: 0.5, annotation_source: "llm"
    )
    retriever = instance_double(SFL::Store::PgHybridRetriever, retrieve: [row])
    synthesizer = -> (_) { { answer: "a", confidence: "not a float", cited_clause_numbers: [] } }
    logger = instance_spy(SFL::Core::Ports::JournaldLogger)

    result = described_class.new(retriever:, synthesizer:, logger:).synthesize("what happened?")

    expect(result.answer).to be_nil
    expect(logger).to have_received(:warn).with(
      a_string_including("invalid synthesizer output"),
      query: "what happened?", error_message: a_kind_of(String)
    )
  end
end
