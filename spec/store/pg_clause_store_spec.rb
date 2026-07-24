# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgClauseStore do
  subject(:store) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  it_behaves_like "a clause store port"

  # PgClauseStore only ever persists AnnotatedClause#id as the join key
  # (external_id / clause_id) — SyntacticClause#id, IdeationalPayload#
  # clause_id, and InterpersonalPayload#clause_id all collapse to it on
  # reconstruction (see the class comment). Building fixtures with every id
  # already equal to the outer AnnotatedClause#id makes the round trip
  # exact, matching how a real caller would assert equality without also
  # asserting on the (deliberately not preserved) inner ids.
  # rubocop:disable Metrics/MethodLength -- one full AnnotatedClause fixture literal, not
  # branching logic; splitting it into helpers would obscure the exact shape being asserted.
  def build_clause(id:, document_id:, sentence_index: 0, mood: "declarative", process_type: "material")
    SFL::Core::Types::AnnotatedClause.new(
      id:,
      text: "The system processed #{id}.",
      syntactic: SFL::Core::Types::SyntacticClause.new(
        id:,
        text: "The system processed #{id}.",
        tokens: [
          SFL::Core::Types::SyntacticToken.new(
            text: "processed", lemma: "process", pos: "VERB", tag: "VBD",
            dep: "ROOT", head_index: -1, morphology: { "Tense" => "Past" }, index: 1
          ),
        ],
        groups: [
          SFL::Core::Types::SyntacticGroup.new(
            id: "grp-#{id}", type: "nominal", text: "The system",
            head_token_index: 0, token_indices: [0]
          ),
        ],
        root_index: 0,
        sentence_index:,
        document_id:
      ),
      ideational: SFL::Core::Types::IdeationalPayload.new(
        clause_id: id,
        process_type:,
        participants: [SFL::Core::Types::Participant.new(role: "actor", text: "The system")],
        circumstances: ["quickly"],
        raw_transitivity: { "process" => process_type }
      ),
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: id,
        mood:,
        modality_weight: 0.7,
        tenor: 0.4,
        speaker_attitude: "neutral",
        reasoning: "clear declarative structure",
        annotation_source: "llm",
        reasoning_trace: SFL::Core::Types::ReasoningTrace.new(
          premises: [
            SFL::Core::Types::Premise.new(type: "pos_tag", source: "spacy", value: "VBD", weight: 0.9),
          ],
          inference_rule: "past_tense_declarative",
          conclusion: { "mood" => mood },
          confidence: 0.85,
          derivation_hash: "abc123",
          generated_at: Time.at(1_700_000_000).utc
        )
      ),
      document_id:,
      compiled_at: Time.at(1_700_000_100).utc
    )
  end
  # rubocop:enable Metrics/MethodLength

  describe "#replace_document" do
    it "creates clause, ideational, and interpersonal rows atomically" do
      clause = build_clause(id: "c-1", document_id: "doc-1")

      store.replace_document("doc-1", [clause])

      expect(db[:clauses].where(external_id: "c-1").count).to eq(1)
      expect(db[:ideational_payloads].where(clause_id: "c-1").count).to eq(1)
      expect(db[:interpersonal_payloads].where(clause_id: "c-1").count).to eq(1)
    end

    it "does not leave stale rows behind when the same document is replaced again (F7)" do
      first = build_clause(id: "c-1", document_id: "doc-1")
      store.replace_document("doc-1", [first])

      second = build_clause(id: "c-2", document_id: "doc-1")
      store.replace_document("doc-1", [second])

      expect(db[:clauses].where(document_id: "doc-1").select_map(:external_id)).to eq(["c-2"])
      expect(db[:ideational_payloads].where(clause_id: "c-1").count).to eq(0)
      expect(db[:interpersonal_payloads].where(clause_id: "c-1").count).to eq(0)
      expect(db[:clauses].count).to eq(1)
    end

    it "leaves other documents' clauses untouched" do
      store.replace_document("doc-1", [build_clause(id: "c-1", document_id: "doc-1")])
      store.replace_document("doc-2", [build_clause(id: "c-2", document_id: "doc-2")])

      store.replace_document("doc-1", [build_clause(id: "c-3", document_id: "doc-1")])

      expect(db[:clauses].where(document_id: "doc-2").select_map(:external_id)).to eq(["c-2"])
    end

    it "is a no-op that clears existing rows when given an empty array" do
      store.replace_document("doc-1", [build_clause(id: "c-1", document_id: "doc-1")])

      store.replace_document("doc-1", [])

      expect(db[:clauses].where(document_id: "doc-1").count).to eq(0)
    end

    # F11: clause_row (see PgClauseStore) never sets embedding_status —
    # every newly-inserted clause must pick up the column's own DB-level
    # default ("pending", db/migrations/008) via multi_insert, not a Ruby-
    # side literal. Live-verified rather than assumed, per this codebase's
    # own precedent of not trusting a Sequel/pg driver default without a
    # real round trip (see Store::Database's UTC timezone comment).
    it "defaults embedding_status to pending via the DB column default, not clause_row (F11)" do
      store.replace_document("doc-1", [build_clause(id: "c-1", document_id: "doc-1")])

      row = db[:clauses].where(external_id: "c-1").first
      expect(row[:embedding_status]).to eq("pending")
      expect(row[:embedding_error]).to be_nil
    end
  end

  describe "#find_by_document" do
    it "round-trips a full AnnotatedClause, including jsonb tokens/groups/participants/reasoning_trace" do
      clause = build_clause(id: "c-1", document_id: "doc-1")

      store.replace_document("doc-1", [clause])
      found = store.find_by_document("doc-1")

      expect(found).to eq([clause])
    end

    it "orders results by sentence_index" do
      first = build_clause(id: "c-1", document_id: "doc-1", sentence_index: 1)
      second = build_clause(id: "c-2", document_id: "doc-1", sentence_index: 0)

      store.replace_document("doc-1", [first, second])

      expect(store.find_by_document("doc-1").map(&:id)).to eq(%w[c-2 c-1])
    end

    it "returns an empty array for a document with no clauses" do
      expect(store.find_by_document("missing-doc")).to eq([])
    end
  end

  describe "foreign key cascade" do
    it "deletes ideational, interpersonal, and embedding rows when a clauses row is deleted directly (D5)" do
      clause = build_clause(id: "c-1", document_id: "doc-1")
      store.replace_document("doc-1", [clause])
      db[:embeddings].insert(clause_id: "c-1", embedding: Pgvector.encode(Array.new(768, 0.01)), model: "test-model")

      db[:clauses].where(external_id: "c-1").delete

      expect(db[:ideational_payloads].where(clause_id: "c-1").count).to eq(0)
      expect(db[:interpersonal_payloads].where(clause_id: "c-1").count).to eq(0)
      expect(db[:embeddings].where(clause_id: "c-1").count).to eq(0)
    end
  end
end
