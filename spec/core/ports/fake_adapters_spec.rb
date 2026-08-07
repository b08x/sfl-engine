# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::Classifier do
  subject { described_class.new(results:) }

  let(:results) do
    {
      "chatgpt-shaped sample" => SFL::Core::Types::ClassificationResult.new(
        format: "chatgpt_export", mode: "conversation", confidence: 0.95, reasoning: "has a mapping key"
      ),
    }
  end

  it_behaves_like "a classifier port"

  it "returns the registered result for an exact sample match" do
    result = subject.classify("chatgpt-shaped sample", "some/path.txt")

    expect(result.format).to eq("chatgpt_export")
    expect(result.confidence).to eq(0.95)
  end

  it "returns a low-confidence unknown default for an unregistered sample" do
    result = subject.classify("never registered", "some/path.txt")

    expect(result.format).to eq("unknown")
    expect(result.confidence).to eq(0.0)
  end

  it "ignores path when looking up a registered sample" do
    a = subject.classify("chatgpt-shaped sample", "some/path.txt")
    b = subject.classify("chatgpt-shaped sample", "a/totally/different/path.json")

    expect(a).to eq(b)
  end
end

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

RSpec.describe SFL::Core::Ports::Fake::EmbeddingStore do
  subject { described_class.new }

  it_behaves_like "an embedding store port"

  it "returns exactly what was written for a document_id" do
    subject.replace_document("doc-1", { "ann-1" => [0.1, 0.2] })

    expect(subject.find_by_document("doc-1")).to eq({ "ann-1" => [0.1, 0.2] })
  end
end
