# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgIngestReviewRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  describe "#enqueue" do
    it "inserts a pending row and returns its id" do
      id = repo.enqueue(
        path: "export-dump/weird_chat.jsonl", status: "loader_drafted",
        format: "unknown", mode: nil, confidence: 0.2,
        reasoning: "JSONL rows resembling a chat log, but no loader recognizes this shape",
        loader_path: "lib/sfl/core/loaders/generic_jsonl_chat_source.rb",
        doc_path: "docs/ingest-review/generic_jsonl_chat_source.md"
      )

      row = db[:ingest_review_entries].where(id:).first
      expect(row).to include(
        path: "export-dump/weird_chat.jsonl", status: "loader_drafted",
        format: "unknown", confidence: 0.2,
        loader_path: "lib/sfl/core/loaders/generic_jsonl_chat_source.rb"
      )
      expect(row[:mode]).to be_nil
      expect(row[:resolved_at]).to be_nil
    end

    it "defaults status to pending when not given" do
      id = repo.enqueue(path: "a.md", reasoning: "ambiguous mode")

      expect(db[:ingest_review_entries].where(id:).first[:status]).to eq("pending")
    end

    it "coerces a Symbol format to String (same Sequel boundary guarantee as " \
      "PgReviewQueueRepository#enqueue: a bare Symbol renders as an unquoted SQL identifier)" do
      id = repo.enqueue(path: "a.md", reasoning: "ambiguous", format: :markdown)

      expect(db[:ingest_review_entries].where(id:).first[:format]).to eq("markdown")
    end

    it "coerces a Symbol mode to String (same Sequel boundary guarantee)" do
      id = repo.enqueue(path: "a.md", reasoning: "ambiguous", mode: :conversation)

      expect(db[:ingest_review_entries].where(id:).first[:mode]).to eq("conversation")
    end
  end

  describe "#find" do
    it "returns the row for a known id" do
      id = repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")

      expect(repo.find(id)[:path]).to eq("a.md")
    end

    it "returns nil for an unknown id" do
      expect(repo.find("missing")).to be_nil
    end
  end

  describe "#resolved?" do
    it "is false for a path with no review entry at all" do
      expect(repo.resolved?("never-seen.md")).to be(false)
    end

    it "is false for a path with only an unresolved entry" do
      repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")

      expect(repo.resolved?("a.md")).to be(false)
    end

    it "is true once that path's row has status resolved" do
      id = repo.enqueue(path: "a.md", status: "low_confidence_mode", reasoning: "ambiguous")
      db[:ingest_review_entries].where(id:).update(status: "resolved", resolved_at: Time.now)

      expect(repo.resolved?("a.md")).to be(true)
    end
  end
end
