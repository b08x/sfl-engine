# frozen_string_literal: true

require "spec_helper"

# Facts 16 and 17 against the in-memory adapter.
RSpec.describe SFL::Core::Ports::Fake::SectionRegistry do
  let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil) }

  def unit(id, **attrs) = SFL::Core::Types::Unit.new(section_id: id, text: "t", document_key: "doc", **attrs)

  it "records the document in its collection and its sections in order" do
    registry = described_class.new(collection: " Papers ")
    registry.register(unit("doc#a", heading: "A", metadata: { "heading_level" => 1 }), 3)
    registry.register(unit("doc#b", parent_section_id: "doc#a", speaker: "Bo"), 2)

    expect(registry.documents["doc"]).to include(collection: "Papers", section_count: 2)
    expect(registry.sections["doc#b"]).to include(ordinal: 2, parent_section_id: "doc#a", kind: "turn", label: "Bo")
  end

  it "moves a document from another collection and warns naming both" do
    registry = described_class.new(collection: "new", logger:, documents: { "doc" => { collection: "old" } })
    registry.register(unit("doc#a"), 1)

    expect(registry.documents["doc"][:collection]).to eq("new")
    expect(logger).to have_received(:warn)
      .with("document moved", document_key: "doc", from_collection: "old", to_collection: "new")
  end

  it "replaces the earlier sections of a re-ingested document" do
    sections = { "doc#old" => { document_key: "doc" } }
    registry = described_class.new(collection: "c", documents: { "doc" => { collection: "c" } }, sections:)
    registry.register(unit("doc#new"), 1)

    expect(registry.sections.keys).to eq(["doc#new"])
    expect(registry.documents["doc"][:updated_at]).to be_a(Time)
  end

  it "replaces a section id the same document already owns without raising" do
    sections = { "doc#a" => { document_key: "doc", ordinal: 1, clause_count: 9 } }
    registry = described_class.new(collection: "c", logger:, documents: { "doc" => { collection: "c" } }, sections:)

    expect { registry.register(unit("doc#a"), 2) }.not_to raise_error
    expect(registry.sections["doc#a"]).to include(document_key: "doc", ordinal: 1, clause_count: 2)
    expect(logger).not_to have_received(:warn)
  end

  it "drops a parent that was never registered" do
    registry = described_class.new(collection: "c")
    registry.register(unit("doc#a", parent_section_id: "doc#missing"), 1)

    expect(registry.sections["doc#a"][:parent_section_id]).to be_nil
  end

  it "runs the transaction block" do
    expect(described_class.new(collection: "c").transaction { 7 }).to eq(7)
  end

  it "does not warn when a document is re-ingested into its own collection" do
    registry = described_class.new(collection: " c ", logger:, documents: { "doc" => { collection: +"c" } })
    registry.register(unit("doc#a"), 1)

    expect(logger).not_to have_received(:warn)
  end

  it "moves a document without raising when no logger is given" do
    registry = described_class.new(collection: "new", documents: { "doc" => { collection: "old" } })

    expect { registry.register(unit("doc#a"), 1) }.not_to raise_error
  end

  it "keeps other documents' sections and counts only this document's sections" do
    sections = { "other#a" => { document_key: "other" }, "other#b" => { document_key: "other" } }
    registry = described_class.new(collection: "c", documents: { "other" => { collection: "c", section_count: 2 } }, sections:)
    registry.register(unit("doc#a"), 4)

    expect(registry.sections.keys).to eq(%w[other#a other#b doc#a])
    expect(registry.documents["doc"][:section_count]).to eq(1)
    expect(registry.sections["doc#a"]).to include(document_key: "doc", ordinal: 1, clause_count: 4)
  end

  it "returns nil from #register" do
    expect(described_class.new(collection: "c").register(unit("doc#a"), 1)).to be_nil
  end

  # Seeded hashes may omit keys; the fake reads them as nil rather than raising.
  it "treats a seeded document without a collection as moved and keeps a section without a document key" do
    sections = { "loose" => {} }
    registry = described_class.new(collection: "c", logger:, documents: { "doc" => {} }, sections:)
    registry.register(unit("doc#a"), 1)

    expect(logger).to have_received(:warn)
      .with("document moved", document_key: "doc", from_collection: nil, to_collection: "c")
    expect(registry.sections.keys).to eq(%w[loose doc#a])
    expect(registry.documents["doc"][:section_count]).to eq(1)
  end

  describe "a section id stored under another document" do
    let(:sections) { { "doc#a" => { document_key: "other", ordinal: 1 } } }
    let(:documents) { { "other" => { collection: "c", section_count: 1 } } }
    let(:registry) { described_class.new(collection: "c", logger:, documents:, sections:) }

    it "raises ConflictError and changes nothing" do
      expect { registry.register(unit("doc#a"), 2) }
        .to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError, /doc#a belongs to other, not doc/)
      expect(registry.sections).to eq("doc#a" => { document_key: "other", ordinal: 1 })
      expect(registry.documents.keys).to eq(["other"])
    end

    it "logs a warning with the section id and both document keys" do
      expect { registry.register(unit("doc#a"), 2) }.to raise_error(SFL::Core::Ports::SectionRegistry::ConflictError)
      expect(logger).to have_received(:warn)
        .with("section owned by another document", section_id: "doc#a", document_key: "doc", owner_document_key: "other")
    end
  end
end
