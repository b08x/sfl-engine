# frozen_string_literal: true

require "spec_helper"

# Browse reads the M1 data model (collections, documents, nested sections)
# and both review flows through this adapter.
RSpec.describe SFL::Store::PgBrowseSource do
  subject(:source) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:collection_id) { SFL::Store::PgCollectionRepository.new(db).find_or_create("papers")[:id] }
  let(:document_id) do
    SFL::Store::PgDocumentRepository.new(db).upsert(collection_id:, document_key: "paper.md", source_path: "/data/paper.md",
      title: "Paper")[:id]
  end
  let(:sections) { SFL::Store::PgSectionRepository.new(db) }

  before do
    SFL::Store::StoreTestDb.clean!
    sections.upsert(document_id, "paper.md#intro", ordinal: 1, kind: "heading", label: "Intro", level: 1, clause_count: 1)
    sections.upsert(document_id, "paper.md#background", ordinal: 2, kind: "heading", label: "Background", level: 2,
      parent_section_id: "paper.md#intro", clause_count: 1)
    insert_clause("c-1", "paper.md#intro", annotation_source: "stub", trace: trace(0.4))
    insert_clause("c-2", "paper.md#background", annotation_source: "stub")
  end

  def trace(confidence)
    {
      "premises" => [],
      "inference_rule" => "rule",
      "conclusion" => {},
      "confidence" => confidence,
      "derivation_hash" => "h",
      "generated_at" => "2026-10-17T09:00:00Z",
    }
  end

  def insert_clause(id, section_id, annotation_source:, trace: nil)
    db[:clauses].insert(external_id: id, text: "clause #{id}", section_id:, sentence_index: 0, root_index: 0)
    db[:ideational_payloads].insert(clause_id: id, process_type: "material")
    db[:interpersonal_payloads].insert(clause_id: id, mood: "declarative", modality_weight: 0.5, tenor: 0.5, annotation_source:,
      reasoning_trace: trace && Sequel.pg_jsonb_wrap(trace))
  end

  it "lists collections, their documents and the nested section tree" do
    expect(source.collections).to eq([{ id: collection_id, name: "papers" }])
    expect(source.documents(collection_id)).to eq([
{
  id: document_id,
  document_key: "paper.md",
  title: "Paper",
  source_path: "/data/paper.md",
},
])
    expect(source.sections(document_id)).to match([
      hash_including(section_id: "paper.md#intro", label: "Intro", ordinal: 1, clause_count: 1,
        children: [hash_including(section_id: "paper.md#background", children: [])]),
    ])
  end

  it "reads a section's clauses with their payloads" do
    expect(source.clauses("paper.md#intro")).to match([
      hash_including(id: "c-1", text: "clause c-1", section_id: "paper.md#intro",
        ideational: hash_including(process_type: "material"), interpersonal: hash_including(mood: "declarative")),
    ])
  end

  it "returns pending and decided content-review items" do
    queue = SFL::Store::PgReviewQueueRepository.new(db)
    pending = queue.enqueue(section_id: "paper.md#intro", modality: "image", source_file: "/f.png", generated_text: "g", reason: "image")
    decided = queue.enqueue(section_id: "paper.md#background", modality: "text", source_file: "/f.txt", generated_text: "t",
      reason: "fallback_annotation")
    queue.decide(id: decided, decision: "reject")

    expect(source.content_reviews.to_h { |row| [row[:id], row[:status]] }).to eq(pending => "pending", decided => "rejected")
    expect(source.content_reviews.first.keys).to contain_exactly(:id, :section_id, :modality, :source_file, :generated_text, :reason,
      :status)
  end

  it "reports annotation review per clause: pending with confidence, or the latest decision" do
    SFL::Store::PgAnnotationReviewRepository.new(db).record_review(clause_id: "c-2", decision: "accepted", original_annotation_source: "stub")

    expect(source.annotation_reviews).to eq("c-1" => { status: "pending", confidence: 0.4 }, "c-2" => { status: "accepted", confidence: nil })
  end

  it "locates sections in their collection and document" do
    expect(source.locate(["paper.md#background"])).to eq(
      "paper.md#background" => { label: "Background", document_key: "paper.md", source_path: "/data/paper.md", collection: "papers" }
    )
  end
end
