# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "dry/monads"

# Doubles follow this codebase's convention (see spec/analysis/engine_spec.rb):
# instance_double for every real collaborator class Context wires up, so a
# renamed/removed method on any of them fails this spec instead of drifting
# silently. ctx itself is a real API::Context (a plain Struct, nothing to
# fake) holding those doubles.
RSpec.describe SFL::API::Server do
  include Rack::Test::Methods
  include Dry::Monads[:result]

  let(:pipeline) { instance_double(SFL::Core::Pipeline) }
  let(:retriever) { instance_double(SFL::Store::PgHybridRetriever) }
  let(:synthesizer) { instance_double(SFL::Retrieval::ContextSynthesizer) }
  let(:clause_store) { instance_double(SFL::Store::PgClauseStore) }
  let(:review_queue_repo) { instance_double(SFL::Store::PgReviewQueueRepository) }
  let(:annotation_review_repo) { instance_double(SFL::Store::PgAnnotationReviewRepository) }
  let(:pass_two) { instance_double(SFL::LLM::Engine) }

  let(:ctx) do
    SFL::API::Context.new(pipeline:, retriever:, synthesizer:, clause_store:, review_queue_repo:,
      annotation_review_repo:, pass_two:)
  end

  def app
    described_class.new(ctx)
  end

  # rubocop:disable Metrics/MethodLength -- one full AnnotatedClause fixture literal, not
  # branching logic (same rationale spec/store/pg_clause_store_spec.rb's own build_clause disable documents).
  def build_clause(id: "c-1", document_id: "doc-1", mood: "declarative", annotation_source: "llm")
    SFL::Core::Types::AnnotatedClause.new(
      id:, text: "The system processed it.",
      syntactic: SFL::Core::Types::SyntacticClause.new(
        id:, text: "The system processed it.",
        tokens: [
          SFL::Core::Types::SyntacticToken.new(
            text: "processed", lemma: "process", pos: "VERB", tag: "VBD",
            dep: "ROOT", head_index: -1, morphology: {}, index: 1
          ),
        ],
        groups: [], root_index: 0, sentence_index: 0, document_id:
      ),
      ideational: SFL::Core::Types::IdeationalPayload.new(
        clause_id: id, process_type: "material",
        participants: [SFL::Core::Types::Participant.new(role: "actor", text: "The system")],
        circumstances: [], raw_transitivity: {}
      ),
      interpersonal: SFL::Core::Types::InterpersonalPayload.new(
        clause_id: id, mood:, modality_weight: 0.7, tenor: 0.4, speaker_attitude: "neutral",
        reasoning: "clear", annotation_source:, reasoning_trace: nil
      ),
      document_id:, compiled_at: Time.at(1_700_000_000).utc
    )
  end
  # rubocop:enable Metrics/MethodLength

  # ── GET /health ──────────────────────────────────────────────────────────

  describe "GET /health" do
    it "returns 200 with status ok" do
      get "/health"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq("status" => "ok")
    end
  end

  # ── CORS ─────────────────────────────────────────────────────────────────

  describe "CORS" do
    it "echoes the allowed dev origin on a normal request" do
      get "/health", {}, "HTTP_ORIGIN" => "http://localhost:3000"
      expect(last_response.headers["access-control-allow-origin"]).to eq("http://localhost:3000")
    end

    it "omits CORS headers for a non-allowlisted origin" do
      get "/health", {}, "HTTP_ORIGIN" => "https://evil.example"
      expect(last_response.headers).not_to have_key("access-control-allow-origin")
    end

    it "answers an OPTIONS preflight with 204 and the allowed methods/headers" do
      options "/retrieve", {}, "HTTP_ORIGIN" => "http://127.0.0.1:3000"
      expect(last_response.status).to eq(204)
      expect(last_response.headers["access-control-allow-origin"]).to eq("http://127.0.0.1:3000")
      expect(last_response.headers["access-control-allow-methods"]).to include("POST")
    end
  end

  # ── 404 / error handling ─────────────────────────────────────────────────

  describe "unknown route" do
    it "returns 404" do
      get "/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "an unexpected error" do
    it "returns 500 without leaking a bare exception" do
      allow(clause_store).to receive(:find_all).and_raise(RuntimeError, "boom")

      get "/clauses"

      expect(last_response.status).to eq(500)
      expect(JSON.parse(last_response.body)["message"]).to eq("boom")
    end
  end

  # ── POST /pipeline/compile ───────────────────────────────────────────────

  describe "POST /pipeline/compile" do
    it "returns 400 when text is missing" do
      post "/pipeline/compile", JSON.dump({}), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to match(/text is required/i)
    end

    it "compiles synchronously and returns the annotated clauses" do
      clause = build_clause
      allow(pipeline).to receive(:compile)
        .with("hello", document_id: "doc-1", store: false, embed: false, resume: false)
        .and_return(Success([clause]))

      post "/pipeline/compile", JSON.dump({ text: "hello", document_id: "doc-1" }),
        "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body).size).to eq(1)
      expect(JSON.parse(last_response.body).first["id"]).to eq("c-1")
    end

    it "surfaces a compile failure as a 500 (F2's dead endpoint fixed by deletion, not silence)" do
      allow(pipeline).to receive(:compile).and_return(Failure(:sidecar_timeout))

      post "/pipeline/compile", JSON.dump({ text: "hello" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(500)
    end
  end

  # ── POST /retrieve ───────────────────────────────────────────────────────

  describe "POST /retrieve" do
    it "returns 400 when query is missing" do
      post "/retrieve", JSON.dump({}), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns ranked results" do
      result = SFL::Core::Types::RetrievalResult.new(
        clause_id: "c-1", text: "hi", document_id: "doc-1", rrf_score: 0.9
      )
      allow(retriever).to receive(:retrieve).and_return([result])

      post "/retrieve", JSON.dump({ query: "hi", limit: 5 }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["count"]).to eq(1)
      expect(body["results"].first["clause_id"]).to eq("c-1")
    end
  end

  # ── POST /synthesize ─────────────────────────────────────────────────────

  describe "POST /synthesize" do
    it "returns 400 when query is missing" do
      post "/synthesize", JSON.dump({}), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns the synthesis result" do
      result = SFL::Core::Types::SynthesisResult.new(
        query: "hi", answer: "an answer", cited_clause_ids: ["c-1"], clauses: [], retrieved_count: 1, confidence: 0.8
      )
      allow(synthesizer).to receive(:synthesize).and_return(result)

      post "/synthesize", JSON.dump({ query: "hi" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["answer"]).to eq("an answer")
    end
  end

  # ── GET /clauses ─────────────────────────────────────────────────────────

  describe "GET /clauses" do
    it "returns a paginated, filtered listing" do
      clause = build_clause
      allow(clause_store).to receive(:find_all)
        .with(document_id: "doc-1", annotation_source: nil,
          filters: SFL::Core::Types::RetrievalFilters.new, limit: 50, offset: 0)
        .and_return(clauses: [clause], total: 1)

      get "/clauses", document_id: "doc-1"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["total"]).to eq(1)
      expect(body["clauses"].first["id"]).to eq("c-1")
    end
  end

  # ── GET /clauses/review-queue ────────────────────────────────────────────

  describe "GET /clauses/review-queue" do
    it "returns the annotation-confidence review queue" do
      allow(annotation_review_repo).to receive(:review_queue).with(limit: 50, offset: 0)
        .and_return(clauses: [{ id: "c-1" }], total: 1)

      get "/clauses/review-queue"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["total"]).to eq(1)
    end
  end

  # ── POST /clauses/:id/review ─────────────────────────────────────────────

  describe "POST /clauses/:id/review" do
    it "returns 400 for an invalid decision" do
      post "/clauses/c-1/review", JSON.dump({ decision: "bogus" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns 404 when the clause doesn't exist" do
      allow(clause_store).to receive(:find).with("missing").and_return(nil)

      post "/clauses/missing/review", JSON.dump({ decision: "accepted" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(404)
    end

    it "accepted: records the audit row without touching the clause" do
      clause = build_clause
      allow(clause_store).to receive(:find).with("c-1").and_return(clause)
      review = SFL::Core::Types::AnnotationReview.new(
        clause_id: "c-1", decision: "accepted", original_annotation_source: "llm"
      )
      allow(annotation_review_repo).to receive(:record_review)
        .with(clause_id: "c-1", decision: "accepted", original_annotation_source: "llm", reviewer: nil, notes: nil)
        .and_return(review)
      allow(clause_store).to receive(:update_interpersonal)

      post "/clauses/c-1/review", JSON.dump({ decision: "accepted" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["decision"]).to eq("accepted")
      expect(clause_store).not_to have_received(:update_interpersonal)
    end

    it "re_annotated: re-runs Pass 2 only, writes the new interpersonal payload, then records the audit row" do
      clause = build_clause
      allow(clause_store).to receive(:find).with("c-1").and_return(clause)
      new_interpersonal = clause.interpersonal.new(mood: "interrogative")
      allow(pass_two).to receive(:annotate)
        .with(clause.syntactic, clause.ideational)
        .and_return(SFL::Core::Types::AnnotationResult.new(interpersonal: new_interpersonal))
      allow(clause_store).to receive(:update_interpersonal).with("c-1", new_interpersonal)
      review = SFL::Core::Types::AnnotationReview.new(
        clause_id: "c-1", decision: "re_annotated", original_annotation_source: "llm"
      )
      allow(annotation_review_repo).to receive(:record_review).and_return(review)

      post "/clauses/c-1/review", JSON.dump({ decision: "re_annotated" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(clause_store).to have_received(:update_interpersonal).with("c-1", new_interpersonal)
    end
  end

  # ── GET /review-queue ────────────────────────────────────────────────────

  describe "GET /review-queue" do
    it "returns the content-review queue" do
      allow(review_queue_repo).to receive(:pending).with(modality: nil, limit: 50, offset: 0)
        .and_return(items: [{ id: "r-1" }], total: 1)

      get "/review-queue"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["total"]).to eq(1)
    end
  end

  # ── POST /review-queue/:id/decide ────────────────────────────────────────

  describe "POST /review-queue/:id/decide" do
    it "returns 400 for an invalid decision" do
      post "/review-queue/r-1/decide", JSON.dump({ decision: "bogus" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns 400 when decision is edit but edited_text is missing" do
      post "/review-queue/r-1/decide", JSON.dump({ decision: "edit" }), "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns 404 when the review item doesn't exist" do
      allow(review_queue_repo).to receive(:find).with("missing").and_return(nil)

      post "/review-queue/missing/decide", JSON.dump({ decision: "approve" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(404)
    end

    it "approve: marks reviewed without touching clause storage" do
      allow(review_queue_repo).to receive(:find).with("r-1").and_return(id: "r-1", document_id: "doc-1")
      allow(review_queue_repo).to receive(:decide)
        .with(id: "r-1", decision: "approve", edited_text: nil, reviewer: nil)
        .and_return(id: "r-1", status: "approved")
      allow(clause_store).to receive(:replace_document)

      post "/review-queue/r-1/decide", JSON.dump({ decision: "approve" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(clause_store).not_to have_received(:replace_document)
    end

    it "reject: clears the document's stored clauses via replace_document(id, [])" do
      allow(review_queue_repo).to receive(:find).with("r-1").and_return(id: "r-1", document_id: "doc-1")
      allow(clause_store).to receive(:replace_document).with("doc-1", [])
      allow(review_queue_repo).to receive(:decide).and_return(id: "r-1", status: "rejected")

      post "/review-queue/r-1/decide", JSON.dump({ decision: "reject" }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(clause_store).to have_received(:replace_document).with("doc-1", [])
    end

    it "edit: recompiles the document through the pipeline and returns the new clauses" do
      clause = build_clause
      allow(review_queue_repo).to receive(:find).with("r-1").and_return(id: "r-1", document_id: "doc-1")
      allow(pipeline).to receive(:compile)
        .with("edited text", document_id: "doc-1", store: true, embed: true, resume: false)
        .and_return(Success([clause]))
      allow(review_queue_repo).to receive(:decide)
        .with(id: "r-1", decision: "edit", edited_text: "edited text", reviewer: nil)
        .and_return(id: "r-1", status: "edited")

      post "/review-queue/r-1/decide", JSON.dump({ decision: "edit", edited_text: "edited text" }),
        "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["clauses"].first["id"]).to eq("c-1")
    end
  end
end
