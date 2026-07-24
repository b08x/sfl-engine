# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::ClauseStore do
  subject { described_class.new }

  it_behaves_like "a clause store port"

  it "returns exactly what was written for a document_id" do
    clause = SFL::Core::Types::AnnotatedClause.new(
      id: "ann-1", text: "It works.",
      syntactic: SFL::Core::Types::SyntacticClause.new(
        id: "c-1", text: "It works.", tokens: [], root_index: 0, sentence_index: 0, document_id: "doc-1"
      ),
      ideational: SFL::Core::Types::IdeationalPayload.new(
        clause_id: "c-1", process_type: "material",
        participants: [], circumstances: [], raw_transitivity: {}
      ),
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: "c-1", mood: "declarative",
        modality_weight: 0.5, tenor: 0.5,
        speaker_attitude: nil, reasoning: nil, annotation_source: "stub"
      ),
      document_id: "doc-1", compiled_at: Time.now
    )

    subject.replace_document("doc-1", [clause])
    expect(subject.find_by_document("doc-1")).to eq([clause])
  end

  it "replaces, rather than appends to, a document's clauses on a second write" do
    subject.replace_document("doc-1", [:first_write])
    subject.replace_document("doc-1", [:second_write])
    expect(subject.find_by_document("doc-1")).to eq([:second_write])
  end
end

RSpec.describe SFL::Core::Ports::Fake::Cache do
  subject { described_class.new }

  it_behaves_like "a cache port"

  it "returns a previously-written value as a hit in the same #partition call" do
    subject.write("a", "cached-value")
    hits, misses = subject.partition(%w[a b])
    expect(hits).to eq({ "a" => "cached-value" })
    expect(misses).to eq(["b"])
  end
end
