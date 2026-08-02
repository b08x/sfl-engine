# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::API::ClauseReviewService do
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:clause_store) { SFL::Store::PgClauseStore.new(db) }
  let(:annotation_review_repo) { SFL::Store::PgAnnotationReviewRepository.new(db) }
  let(:pass_two) { instance_double(SFL::Core::Ports::Annotator) }
  let(:service) { described_class.new(db:, clause_store:, annotation_review_repo:, pass_two:) }

  before { SFL::Store::StoreTestDb.clean! }

  def insert_clause(id:, document_id: "doc-1", annotation_source: "llm", mood: "declarative")
    db[:clauses].insert(external_id: id, text: "clause #{id}", document_id:, sentence_index: 0, root_index: 0)
    db[:ideational_payloads].insert(clause_id: id, process_type: "material")
    db[:interpersonal_payloads].insert(clause_id: id, mood:, modality_weight: 0.5, tenor: 0.5, annotation_source:)
  end

  describe "#review" do
    it "returns nil for a clause that doesn't exist, without writing an audit row" do
      result = service.review(clause_id: "missing", decision: "accepted")

      expect(result).to be_nil
      expect(db[:annotation_reviews].count).to eq(0)
    end

    it "accepted: records the audit row without touching interpersonal_payloads" do
      insert_clause(id: "c-1", annotation_source: "stub")

      review = service.review(clause_id: "c-1", decision: "accepted", reviewer: "alice")

      expect(review).to be_a(SFL::Core::Types::AnnotationReview)
      expect(db[:annotation_reviews].where(clause_id: "c-1").count).to eq(1)
      expect(db[:interpersonal_payloads].where(clause_id: "c-1").first[:annotation_source]).to eq("stub")
    end

    it "re_annotated: re-runs Pass 2, persists the new interpersonal payload, and records the audit row " \
      "referencing the ORIGINAL annotation_source (snapshotted before the overwrite)" do
      insert_clause(id: "c-1", annotation_source: "stub", mood: "declarative")
      clause = clause_store.find("c-1")
      new_interpersonal = clause.interpersonal.new(mood: "interrogative", annotation_source: "llm")
      allow(pass_two).to receive(:annotate).with(clause.syntactic, clause.ideational)
        .and_return(SFL::Core::Types::AnnotationResult.new(interpersonal: new_interpersonal))

      review = service.review(clause_id: "c-1", decision: "re_annotated")

      expect(review.original_annotation_source).to eq("stub")
      row = db[:interpersonal_payloads].where(clause_id: "c-1").first
      expect(row[:mood]).to eq("interrogative")
      expect(row[:annotation_source]).to eq("llm")
    end

    it "rolls back the interpersonal_payloads write when recording the audit row fails afterward " \
      "(issue #2: both writes must be one transaction, not two independent statements)" do
      insert_clause(id: "c-1", annotation_source: "stub", mood: "declarative")
      clause = clause_store.find("c-1")
      new_interpersonal = clause.interpersonal.new(mood: "interrogative")
      allow(pass_two).to receive(:annotate)
        .and_return(SFL::Core::Types::AnnotationResult.new(interpersonal: new_interpersonal))
      failing_repo = instance_double(SFL::Store::PgAnnotationReviewRepository)
      allow(failing_repo).to receive(:record_review).and_raise(RuntimeError, "boom")
      failing_service = described_class.new(db:, clause_store:, annotation_review_repo: failing_repo, pass_two:)

      expect { failing_service.review(clause_id: "c-1", decision: "re_annotated") }.to raise_error(RuntimeError, "boom")

      row = db[:interpersonal_payloads].where(clause_id: "c-1").first
      expect(row[:mood]).to eq("declarative") # rolled back, not "interrogative"
      expect(db[:annotation_reviews].count).to eq(0)
    end
  end
end
