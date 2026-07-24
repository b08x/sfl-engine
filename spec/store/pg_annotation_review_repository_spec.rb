# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgAnnotationReviewRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  def insert_clause(id:, document_id: "doc-1", annotation_source: "llm", mood: "declarative")
    db[:clauses].insert(
      external_id: id, text: "clause #{id}", document_id:,
      sentence_index: 0, root_index: 0
    )
    db[:ideational_payloads].insert(clause_id: id, process_type: "material")
    db[:interpersonal_payloads].insert(
      clause_id: id, mood:, modality_weight: 0.5, tenor: 0.5, annotation_source:
    )
  end

  describe "#record_review" do
    it "persists a review row and returns a typed AnnotationReview" do
      insert_clause(id: "c-1", annotation_source: "stub")

      review = repo.record_review(
        clause_id: "c-1", decision: "accepted", original_annotation_source: "stub",
        reviewer: "alice", notes: "looks fine"
      )

      expect(review).to be_a(SFL::Core::Types::AnnotationReview)
      expect(db[:annotation_reviews].where(id: review.id).first).to include(
        clause_id: "c-1", decision: "accepted", original_annotation_source: "stub", reviewer: "alice"
      )
    end
  end

  describe "#reviews_for" do
    it "returns review rows for a clause, oldest first" do
      insert_clause(id: "c-1", annotation_source: "stub")
      first = repo.record_review(clause_id: "c-1", decision: "rejected", original_annotation_source: "stub")
      second = repo.record_review(clause_id: "c-1", decision: "accepted", original_annotation_source: "stub")

      rows = repo.reviews_for("c-1")

      expect(rows.map { |r| r[:id] }).to eq([first.id, second.id])
    end
  end

  describe "#review_queue" do
    it "excludes clauses whose annotation_source is trusted" do
      insert_clause(id: "c-trusted", annotation_source: "llm")
      insert_clause(id: "c-untrusted", annotation_source: "stub")

      result = repo.review_queue

      expect(result[:clauses].map { |c| c[:id] }).to contain_exactly("c-untrusted")
    end

    it "excludes clauses a human already accepted (live-verified bug: Accept must clear the queue)" do
      insert_clause(id: "c-1", annotation_source: "stub")

      repo.record_review(clause_id: "c-1", decision: "accepted", original_annotation_source: "stub")

      result = repo.review_queue

      expect(result[:clauses]).to be_empty
      expect(result[:total]).to eq(0)
    end

    it "does NOT exclude rejected decisions (an unresolved disagreement keeps showing up)" do
      insert_clause(id: "c-1", annotation_source: "stub")

      repo.record_review(clause_id: "c-1", decision: "rejected", original_annotation_source: "stub")

      result = repo.review_queue

      expect(result[:clauses].map { |c| c[:id] }).to contain_exactly("c-1")
    end

    it "supports pagination" do
      3.times { |i| insert_clause(id: "c-#{i}", annotation_source: "stub") }

      result = repo.review_queue(limit: 2, offset: 0)

      expect(result[:clauses].size).to eq(2)
      expect(result[:total]).to eq(3)
    end
  end
end
