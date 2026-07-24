# frozen_string_literal: true

# Shared role tests: every concrete adapter for a port (Null, Fake, and
# eventually real ones like SpacySidecarParser) must satisfy these, so a
# new adapter can't quietly drift from the interface the pipeline/chat
# agent code was written against. Each example group expects `subject`
# to be the adapter under test.

RSpec.shared_examples "a syntactic parser port" do
  it "returns an Array of clauses from #parse" do
    expect(subject.parse("The system processed the data.")).to be_an(Array)
  end
end

RSpec.shared_examples "an annotator port" do
  let(:clause) do
    SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "It works.",
      tokens: [
        SFL::Core::Types::SyntacticToken.new(
          text: "works", lemma: "work", pos: "VERB", tag: "VBZ",
          dep: "ROOT", head_index: -1, morphology: {}, index: 0
        ),
      ],
      root_index: 0, sentence_index: 0, document_id: "doc-1"
    )
  end

  let(:ideational) do
    SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material",
      participants: [], circumstances: [], raw_transitivity: {}
    )
  end

  it "returns an AnnotationResult from #annotate" do
    expect(subject.annotate(clause, ideational)).to be_a(SFL::Core::Types::AnnotationResult)
  end

  it "returns one AnnotationResult per pair from #annotate_batch" do
    result = subject.annotate_batch([[clause, ideational], [clause, ideational]])
    expect(result.size).to eq(2)
    expect(result).to all(be_a(SFL::Core::Types::AnnotationResult))
  end
end

RSpec.shared_examples "an embedder port" do
  it "returns an Array from #embed" do
    expect(subject.embed("some text")).to be_an(Array)
  end

  it "returns one vector per input from #embed_batch" do
    result = subject.embed_batch(%w[one two three])
    expect(result.size).to eq(3)
    expect(result).to all(be_an(Array))
  end
end

RSpec.shared_examples "a clause store port" do
  let(:clause) do
    SFL::Core::Types::AnnotatedClause.new(
      id: "ann-1", text: "It works.",
      syntactic: SFL::Core::Types::SyntacticClause.new(
        id: "c-1", text: "It works.",
        tokens: [], root_index: 0, sentence_index: 0, document_id: "doc-1"
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
  end

  it "accepts #replace_document without raising" do
    expect { subject.replace_document("doc-1", [clause]) }.not_to raise_error
  end

  it "returns an Array of clauses from #find_by_document" do
    subject.replace_document("doc-1", [clause])
    expect(subject.find_by_document("doc-1")).to be_an(Array)
  end
end

RSpec.shared_examples "a cache port" do
  it "returns [hits, misses] from #partition, covering every key exactly once" do
    hits, misses = subject.partition(%w[a b c])
    expect(hits).to be_a(Hash)
    expect(misses).to be_an(Array)
    expect(hits.keys + misses).to match_array(%w[a b c])
  end

  it "accepts #write without raising" do
    expect { subject.write("a", "value") }.not_to raise_error
  end
end

RSpec.shared_examples "a breaker port" do
  it "yields the block and returns its value from #call" do
    expect(subject.call("test") { 42 }).to eq(42)
  end
end

RSpec.shared_examples "an instrumenter port" do
  it "yields the block and returns its value from #instrument" do
    expect(subject.instrument("test") { 42 }).to eq(42)
  end
end

RSpec.shared_examples "a progress sink port" do
  it "accepts #start, #advance, and #finish without raising" do
    expect { subject.start(10) }.not_to raise_error
    expect { subject.advance }.not_to raise_error
    expect { subject.advance(by: 3) }.not_to raise_error
    expect { subject.finish }.not_to raise_error
  end
end

RSpec.shared_examples "a logger port" do
  it "accepts a message argument at every severity without raising" do
    expect { subject.debug("d") }.not_to raise_error
    expect { subject.info("i") }.not_to raise_error
    expect { subject.warn("w") }.not_to raise_error
    expect { subject.error("e") }.not_to raise_error
    expect { subject.fatal("f") }.not_to raise_error
  end

  it "accepts a block form at every severity without raising" do
    expect { subject.debug { "d" } }.not_to raise_error
    expect { subject.info { "i" } }.not_to raise_error
    expect { subject.warn { "w" } }.not_to raise_error
    expect { subject.error { "e" } }.not_to raise_error
    expect { subject.fatal { "f" } }.not_to raise_error
  end
end
