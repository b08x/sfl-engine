# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::RetrievalResult do
  it "requires clause_id, text, and rrf_score" do
    result = described_class.new(clause_id: "c-1", text: "It works.", document_id: "doc-1", rrf_score: 0.5)

    expect(result.clause_id).to eq("c-1")
    expect(result.text).to eq("It works.")
    expect(result.rrf_score).to eq(0.5)
  end

  it "defaults semantic_rank, keyword_rank, mood, tenor, and process_type to nil" do
    result = described_class.new(clause_id: "c-1", text: "It works.", document_id: "doc-1", rrf_score: 0.5)

    expect(result.semantic_rank).to be_nil
    expect(result.keyword_rank).to be_nil
    expect(result.mood).to be_nil
    expect(result.tenor).to be_nil
    expect(result.process_type).to be_nil
  end

  it "accepts a nil document_id (keyword-only clauses may have none)" do
    expect do
      described_class.new(clause_id: "c-1", text: "It works.", document_id: nil, rrf_score: 0.5)
    end.not_to raise_error
  end

  it "accepts inlined mood/tenor/process_type metadata" do
    result = described_class.new(
      clause_id: "c-1", text: "It works.", document_id: "doc-1", rrf_score: 0.5,
      semantic_rank: 1, keyword_rank: 2, mood: "declarative", tenor: 0.5, process_type: "material"
    )

    expect(result.mood).to eq("declarative")
    expect(result.tenor).to eq(0.5)
    expect(result.process_type).to eq("material")
  end

  it "round-trips through Wire.dump/Types::RetrievalResult.new (no Time attributes, so no Wire.load_* is needed)" do
    result = described_class.new(
      clause_id: "c-1", text: "It works.", document_id: "doc-1", rrf_score: 0.5,
      semantic_rank: 1, keyword_rank: nil, mood: "declarative", tenor: 0.5, process_type: "material"
    )

    dumped = SFL::Core::Wire.dump(result)
    reloaded = described_class.new(dumped)

    expect(reloaded).to eq(result)
  end
end
