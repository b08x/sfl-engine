# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgReviewQueueRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  describe "#enqueue" do
    it "inserts a pending row and returns its id" do
      id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "img.png",
        generated_text: "a description", reason: "image"
      )

      row = db[:review_queue].where(id:).first
      expect(row).to include(
        document_id: "doc-1", modality: "image", generated_text: "a description",
        reason: "image", status: "pending"
      )
    end

    it "coerces a Symbol content_type to String (live-verified Sequel bug: a bare Symbol " \
      "renders as an unquoted SQL identifier, raising PG::UndefinedColumn)" do
      id = repo.enqueue(
        document_id: "doc-1", modality: "text", source_file: "f.txt",
        generated_text: "text", reason: "low_quality_score", content_type: :"text/plain"
      )

      row = db[:review_queue].where(id:).first
      expect(row[:content_type]).to eq("text/plain")
    end
  end

  describe "#find" do
    it "returns the row for a known id" do
      id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "img.png",
        generated_text: "a description", reason: "image"
      )

      expect(repo.find(id)[:document_id]).to eq("doc-1")
    end

    it "returns nil for an unknown id" do
      expect(repo.find("missing")).to be_nil
    end
  end

  describe "#pending" do
    it "returns only pending rows, filtered by modality when given" do
      image_id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "a.png",
        generated_text: "a", reason: "image"
      )
      repo.enqueue(
        document_id: "doc-1", modality: "audio", source_file: "a.wav",
        generated_text: "b", reason: "audio_transcript"
      )
      approved_id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "c.png",
        generated_text: "c", reason: "image"
      )
      repo.decide(id: approved_id, decision: "approve")

      result = repo.pending(modality: "image")

      expect(result[:items].map { |i| i[:id] }).to contain_exactly(image_id)
      expect(result[:total]).to eq(1)
    end
  end

  describe "#decide" do
    it "round-trips approve/edit/reject to their mapped status" do
      id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "a.png",
        generated_text: "a", reason: "image"
      )

      updated = repo.decide(id:, decision: "approve", reviewer: "bob")

      expect(updated[:status]).to eq("approved")
      expect(updated[:reviewer]).to eq("bob")
      expect(updated[:reviewed_at]).not_to be_nil
    end

    it "returns nil for an unknown id" do
      expect(repo.decide(id: "missing", decision: "approve")).to be_nil
    end

    it "raises on an unrecognized decision" do
      id = repo.enqueue(
        document_id: "doc-1", modality: "image", source_file: "a.png",
        generated_text: "a", reason: "image"
      )

      expect { repo.decide(id:, decision: "nope") }.to raise_error(ArgumentError)
    end
  end
end
