# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::SectionShape do
  def unit(**attrs) = SFL::Core::Types::Unit.new(section_id: "file#x", text: "t", **attrs)

  describe ".document_key" do
    it "uses the unit's document_key when present" do
      expect(described_class.document_key(unit(document_key: "/p/file.md"))).to eq("/p/file.md")
    end

    it "falls back to the section id prefix before #" do
      expect(described_class.document_key(unit)).to eq("file")
    end
  end

  describe ".attributes" do
    it "labels a turn with its speaker and gives it no level (fact 14)" do
      expect(described_class.attributes(unit(speaker: "Alice", heading: "ignored")))
        .to eq(kind: "turn", label: "Alice", level: nil)
    end

    it "labels a heading section with its heading and level" do
      expect(described_class.attributes(unit(heading: "Scope", metadata: { "heading_level" => 2 })))
        .to eq(kind: "heading", label: "Scope", level: 2)
    end

    it "calls anything else a block" do
      expect(described_class.attributes(unit)).to eq(kind: "block", label: nil, level: nil)
    end
  end

  describe ".document" do
    it "takes the conversation title when there is one" do
      doc = described_class.document(unit(document_key: "c-1", source_path: "/x/export.json",
        metadata: { "conversation_title" => "Chat" }))

      expect(doc).to eq(document_key: "c-1", source_path: "/x/export.json", title: "Chat", source_type: nil)
    end

    it "titles a file by its basename" do
      expect(described_class.document(unit(document_key: "/p/notes.md"))[:title]).to eq("notes.md")
    end
  end
end
