# frozen_string_literal: true

require "spec_helper"
require "pgvector"

RSpec.describe SFL::Store::PgHybridRetriever do
  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  # Inserts one clauses/ideational_payloads/interpersonal_payloads row set —
  # PgHybridRetriever inner-joins both payload tables (to push
  # RetrievalFilters into SQL), so every fixture clause needs both, the same
  # way a real PgClauseStore#replace_section write would produce them.
  # rubocop:disable Metrics/ParameterLists -- one flat fixture-row builder, every
  # parameter maps straight to a column this spec's examples need to control.
  def seed_clause(
    external_id:, text:, section_id: "doc-1", mood: "declarative",
    process_type: "material", source_type: "unspecified",
    modality_weight: 0.5, annotation_source: "llm"
  )
    db[:clauses].insert(
      external_id:, text:, section_id:, sentence_index: 0, root_index: 0, source_type:
    )
    db[:ideational_payloads].insert(clause_id: external_id, process_type:)
    db[:interpersonal_payloads].insert(clause_id: external_id, mood:, modality_weight:, annotation_source:)
  end
  # rubocop:enable Metrics/ParameterLists

  def seed_embedding(clause_id:, vector:, model: "test-model")
    db[:embeddings].insert(clause_id:, embedding: Pgvector.encode(vector), model:)
  end

  def zero_vector(hot_index: nil)
    Array.new(768, 0.0).tap { |v| v[hot_index] = 1.0 if hot_index }
  end

  describe "Reciprocal Rank Fusion (pure calculation, mirrors legacy's isolated unit test)" do
    it "gives the same score to two items with symmetric ranks across both arms" do
      k = described_class::RRF_K

      # Item A: rank 1 in semantic, rank 2 in keyword
      score_a = (1.0 / (k + 1)) + (1.0 / (k + 2))
      # Item B: rank 2 in semantic, rank 1 in keyword
      score_b = (1.0 / (k + 2)) + (1.0 / (k + 1))

      expect(score_a).to be_within(0.0000001).of(score_b)
    end

    it "scores an item appearing in both lists higher than one appearing in only one" do
      k = described_class::RRF_K

      score_a = (1.0 / (k + 1)) + (1.0 / (k + 2)) # appears in both arms
      score_c = 1.0 / (k + 1) # appears in one arm only, at the same rank

      expect(score_a).to be > score_c
    end
  end

  describe "#retrieve, keyword-only (Null::Embedder skips the semantic arm gracefully)" do
    subject(:retriever) { described_class.new(db:, embedder: SFL::Core::Ports::Null::Embedder.new) }

    before do
      seed_clause(external_id: "c-1", text: "widget widget widget widget widget")
      seed_clause(external_id: "c-2", text: "an unrelated sentence about gardening")
    end

    it "returns the matching clause with a keyword_rank and no semantic_rank" do
      query = SFL::Core::Types::RetrievalQuery.new(query: "widget")

      results = retriever.retrieve(query)

      expect(results.map(&:clause_id)).to eq(["c-1"])
      expect(results.first.keyword_rank).to eq(1)
      expect(results.first.semantic_rank).to be_nil
    end

    it "does not raise when the embedder returns an empty vector for the query" do
      query = SFL::Core::Types::RetrievalQuery.new(query: "widget")

      expect { retriever.retrieve(query) }.not_to raise_error
    end
  end

  describe "#retrieve, semantic + keyword combined" do
    subject(:retriever) do
      described_class.new(
        db:,
        embedder: SFL::Core::Ports::Fake::Embedder.new(vectors: { "widget" => zero_vector(hot_index: 0) })
      )
    end

    before do
      # c-1 matches both arms: keyword text contains "widget" AND its stored
      # embedding is identical to the query embedding (cosine distance 0).
      seed_clause(external_id: "c-1", text: "widget widget widget")
      seed_embedding(clause_id: "c-1", vector: zero_vector(hot_index: 0))

      # c-2 matches keyword only.
      seed_clause(external_id: "c-2", text: "widget mentioned once")
      seed_embedding(clause_id: "c-2", vector: zero_vector(hot_index: 1))

      # c-3 matches semantic only (identical embedding, no keyword overlap).
      seed_clause(external_id: "c-3", text: "completely unrelated gardening text")
      seed_embedding(clause_id: "c-3", vector: zero_vector(hot_index: 0))
    end

    it "ranks the clause appearing in both arms above clauses appearing in only one" do
      query = SFL::Core::Types::RetrievalQuery.new(query: "widget")

      results = retriever.retrieve(query)

      expect(results.first.clause_id).to eq("c-1")
      expect(results.map(&:clause_id)).to include("c-2", "c-3")
    end
  end

  # F8 regression: legacy ran both search arms UNFILTERED at limit*3, merged,
  # THEN filtered — so a selective filter could starve the final result
  # below `limit` even when enough matching rows existed. To prove that
  # concretely: seed far more than `limit*3` high-relevance clauses that do
  # NOT match the filter, plus exactly 2 low-relevance clauses that DO. With
  # limit: 3, candidate_limit is 9 — the 15 high-relevance non-matching
  # clauses would fill (and dominate) any *unfiltered* top-9 keyword window,
  # crowding the 2 matching clauses out of the candidate pool entirely
  # before a post-hoc filter ever saw them. Pushing the filter into the SQL
  # WHERE clause (this implementation) means the candidate pool is built
  # from the matching rows only, so both are found regardless of how the
  # (irrelevant, now-excluded) non-matching rows would have ranked.
  describe "#retrieve with a selective filter (F8 regression)" do
    subject(:retriever) { described_class.new(db:, embedder: SFL::Core::Ports::Null::Embedder.new) }

    before do
      # 15 high-relevance, non-matching (declarative) clauses — would fill
      # an unfiltered limit*3=9 candidate window on their own.
      15.times do |i|
        seed_clause(external_id: "declarative-#{i}", text: "widget widget widget widget widget", mood: "declarative")
      end

      # 2 low-relevance, matching (imperative) clauses — weaker keyword
      # match, so they'd rank outside an unfiltered top-9 window.
      seed_clause(external_id: "imperative-0", text: "please assemble the widget carefully today", mood: "imperative")
      seed_clause(external_id: "imperative-1", text: "now fetch the widget from the shelf please", mood: "imperative")
    end

    it "returns exactly the filter-matching rows, not fewer than exist, even though " \
      "more non-matching candidates exist per arm than the unfiltered window would have surfaced" do
      query = SFL::Core::Types::RetrievalQuery.new(
        query: "widget", limit: 3, filters: { mood: "imperative" }
      )

      results = retriever.retrieve(query)

      expect(results.map(&:clause_id)).to contain_exactly("imperative-0", "imperative-1")
    end

    it "returns zero results outside the filter's match set" do
      query = SFL::Core::Types::RetrievalQuery.new(
        query: "widget", limit: 3, filters: { mood: "imperative" }
      )

      results = retriever.retrieve(query)

      expect(results.map(&:mood)).to all(eq("imperative"))
    end
  end

  describe "#retrieve with a source_type filter" do
    subject(:retriever) { described_class.new(db:, embedder: SFL::Core::Ports::Null::Embedder.new) }

    before do
      seed_clause(external_id: "c-1", text: "widget widget widget", source_type: "chat_native")
      seed_clause(external_id: "c-2", text: "widget widget widget", source_type: "vault_markdown")
    end

    it "keeps only clauses matching the source_type filter" do
      query = SFL::Core::Types::RetrievalQuery.new(query: "widget", filters: { source_type: "vault_markdown" })

      results = retriever.retrieve(query)

      expect(results.map(&:clause_id)).to eq(["c-2"])
    end
  end

  # ContextSynthesizer needs modality_weight/annotation_source inlined onto
  # RetrievalResult the same way mood/tenor/process_type already are, so it
  # never needs a second per-clause DB round-trip to partition citable vs
  # fallback-sourced rows (see SFL::Retrieval::ContextSynthesizer).
  describe "#retrieve inlines modality_weight and annotation_source (no second lookup needed)" do
    subject(:retriever) { described_class.new(db:, embedder: SFL::Core::Ports::Null::Embedder.new) }

    before do
      seed_clause(external_id: "c-1", text: "widget widget widget", modality_weight: 0.75, annotation_source: "human")
    end

    it "returns the stored modality_weight and annotation_source on the ranked row" do
      query = SFL::Core::Types::RetrievalQuery.new(query: "widget")

      results = retriever.retrieve(query)

      expect(results.first.modality_weight).to eq(0.75)
      expect(results.first.annotation_source).to eq("human")
    end
  end

  describe ".model_family" do
    it "removes the :tag and one trailing -<digits>" do
      expect(described_class::ModelFilter.model_family("embeddinggemma:latest")).to eq("embeddinggemma")
      expect(described_class::ModelFilter.model_family("embeddinggemma-2:440m")).to eq("embeddinggemma")
    end

    it "keeps a model name that has no tag and no trailing -<digits>" do
      expect(described_class::ModelFilter.model_family("google/gemma-4-26b-a4b-it:free")).to eq("google/gemma-4-26b-a4b-it")
      expect(described_class::ModelFilter.model_family("llama3")).to eq("llama3")
    end
  end

  describe "#retrieve model filter (family:, model:)" do
    subject(:retriever) do
      described_class.new(db:, embedder: SFL::Core::Ports::Fake::Embedder.new(vectors: { "widget" => zero_vector(hot_index: 0) }))
    end

    let(:query) { SFL::Core::Types::RetrievalQuery.new(query: "widget") }

    before do
      seed_clause(external_id: "c-old", text: "widget one")
      seed_clause(external_id: "c-new", text: "widget two")
      seed_clause(external_id: "c-other", text: "widget three")
      seed_clause(external_id: "c-unembedded", text: "widget four")
      seed_embedding(clause_id: "c-old", vector: zero_vector(hot_index: 0), model: "embeddinggemma:latest")
      seed_embedding(clause_id: "c-new", vector: zero_vector(hot_index: 0), model: "embeddinggemma-2:440m")
      seed_embedding(clause_id: "c-other", vector: zero_vector(hot_index: 0), model: "other-model:latest")
    end

    it "returns rows from every model when neither keyword is given (no filter)" do
      expect(retriever.retrieve(query).map(&:clause_id))
        .to contain_exactly("c-old", "c-new", "c-other", "c-unembedded")
    end

    it "keeps only the stored models of the family when family: is given" do
      expect(retriever.retrieve(query, family: "embeddinggemma").map(&:clause_id)).to contain_exactly("c-old", "c-new")
    end

    it "keeps only the exact stored model when model: is given" do
      expect(retriever.retrieve(query, model: "embeddinggemma:latest").map(&:clause_id)).to eq(["c-old"])
    end

    it "does not treat a family name as an exact model" do
      expect(retriever.retrieve(query, model: "embeddinggemma")).to eq([])
    end

    it "lets model: win over family: when both are given" do
      expect(retriever.retrieve(query, family: "embeddinggemma", model: "other-model:latest").map(&:clause_id))
        .to eq(["c-other"])
    end

    it "returns no rows for a family with no stored models" do
      expect(retriever.retrieve(query, family: "nothing-here")).to eq([])
    end
  end

  describe "archived documents are excluded by default" do
    subject(:retriever) { described_class.new(db:, embedder: SFL::Core::Ports::Null::Embedder.new) }

    # One document with one section per key; the clause's section_id points at it.
    def seed_document(key, archived:)
      doc_id = db[:documents].insert(
        collection_id: db[:collections].get(:id) || db[:collections].insert(name: "claude-chats"),
        document_key: key,
        source_path: "/x/#{key}.json", archived_at: (Time.now if archived)
      )
      db[:sections].insert(section_id: "#{key}#turn-0", document_id: doc_id, ordinal: 0, kind: "turn")
    end

    before do
      seed_document("doc-archived", archived: true)
      seed_document("doc-live", archived: false)
      seed_clause(external_id: "c-archived", text: "a lighthouse keeper", section_id: "doc-archived#turn-0")
      seed_clause(external_id: "c-live", text: "the lighthouse at dusk", section_id: "doc-live#turn-0")
    end

    it "keeps the clause of an archived document out of the keyword arm" do
      results = retriever.retrieve(SFL::Core::Types::RetrievalQuery.new(query: "lighthouse"))

      expect(results.map(&:clause_id)).to eq(["c-live"])
    end

    it "keeps the clause of an archived document out of the semantic arm" do
      semantic = described_class.new(
        db:,
        embedder: SFL::Core::Ports::Fake::Embedder.new(vectors: { "lighthouse" => zero_vector(hot_index: 0) })
      )
      seed_embedding(clause_id: "c-archived", vector: zero_vector(hot_index: 0))
      seed_embedding(clause_id: "c-live", vector: zero_vector(hot_index: 1))

      results = semantic.retrieve(SFL::Core::Types::RetrievalQuery.new(query: "lighthouse"))

      expect(results.map(&:clause_id)).to eq(["c-live"])
    end

    it "returns the archived clause again once its document is unarchived" do
      db[:documents].where(document_key: "doc-archived").update(archived_at: nil)

      results = retriever.retrieve(SFL::Core::Types::RetrievalQuery.new(query: "lighthouse"))

      expect(results.map(&:clause_id)).to contain_exactly("c-archived", "c-live")
    end
  end
end
