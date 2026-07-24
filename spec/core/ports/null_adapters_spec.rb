# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::SyntacticParser do
  subject { described_class.new }

  it_behaves_like "a syntactic parser port"
end

RSpec.describe SFL::Core::Ports::Null::Annotator do
  subject { described_class.new }

  it_behaves_like "an annotator port"

  it "labels its output annotation_source as stub, not llm" do
    clause = SFL::Core::Types::SyntacticClause.new(
      id: "c-1", text: "x", tokens: [], root_index: 0, sentence_index: 0, document_id: nil
    )
    ideational = SFL::Core::Types::IdeationalPayload.new(
      clause_id: "c-1", process_type: "material",
      participants: [], circumstances: [], raw_transitivity: {}
    )

    result = subject.annotate(clause, ideational)

    expect(result.interpersonal.annotation_source).to eq("stub")
  end
end

RSpec.describe SFL::Core::Ports::Null::Embedder do
  subject { described_class.new }

  it_behaves_like "an embedder port"
end

RSpec.describe SFL::Core::Ports::Null::ClauseStore do
  subject { described_class.new }

  it_behaves_like "a clause store port"

  it "always returns an empty Array from #find_by_document" do
    subject.replace_document("doc-1", [:not_actually_stored])
    expect(subject.find_by_document("doc-1")).to eq([])
  end
end

RSpec.describe SFL::Core::Ports::Null::Cache do
  subject { described_class.new }

  it_behaves_like "a cache port"

  it "always misses" do
    hits, misses = subject.partition(%w[a b])
    expect(hits).to eq({})
    expect(misses).to eq(%w[a b])
  end
end

RSpec.describe SFL::Core::Ports::Null::Breaker do
  subject { described_class.new }

  it_behaves_like "a breaker port"
end

RSpec.describe SFL::Core::Ports::Null::Instrumenter do
  subject { described_class.new }

  it_behaves_like "an instrumenter port"
end

RSpec.describe SFL::Core::Ports::Null::ProgressSink do
  subject { described_class.new }

  it_behaves_like "a progress sink port"
end

RSpec.describe SFL::Core::Ports::Null::Logger do
  subject { described_class.new }

  it_behaves_like "a logger port"
end
