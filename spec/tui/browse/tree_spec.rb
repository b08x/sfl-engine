# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe SFL::TUI::Browse::Tree do
  subject(:tree) { TUISpecSupport.tree }

  it "nests collections, documents and sections, sections by ordinal with children under their parent" do
    expect(tree.roots).to eq(["c:1", "c:2"])
    expect(tree.children("c:1")).to eq(["d:10", "d:11"])
    expect(tree.children("d:10")).to eq(["s:paper.md#intro", "s:paper.md#method"])
    expect(tree.children("s:paper.md#intro")).to eq(["s:paper.md#background"])
    expect(tree.node("s:paper.md#background")).to have_attributes(kind: :section, depth: 3, label: "Background")
  end

  it "labels a document by title, else its key, and a section by label, else its id" do
    expect(tree.node("d:10").label).to eq("Paper")
    expect(tree.node("d:11").label).to eq("talk.srt")
    expect(tree.node("s:note.txt#0").label).to eq("note.txt#0")
  end

  it "walks ancestors, descendants and the enclosing document, collection and section path" do
    id = "s:paper.md#background"

    expect(tree.ancestors(id)).to eq(["s:paper.md#intro", "d:10", "c:1"])
    expect(tree.descendants("d:10")).to eq(["s:paper.md#intro", "s:paper.md#background", "s:paper.md#method"])
    expect(tree.document_of(id).id).to eq("d:10")
    expect(tree.collection_of(id).label).to eq("papers")
    expect(tree.section_path(id).map(&:label)).to eq(%w[Intro Background])
  end

  it "attaches clauses to a section without changing the original tree" do
    loaded = tree.with_clauses("paper.md#intro", TUISpecSupport.clauses["paper.md#intro"])

    expect(loaded.children("s:paper.md#intro")).to eq(["s:paper.md#background", "k:i1", "k:i2"])
    expect(loaded.clauses("s:paper.md#intro").map(&:label)).to eq(["Intro one.", "Intro two."])
    expect(loaded.loaded?("s:paper.md#intro")).to be(true)
    expect(tree.loaded?("s:paper.md#intro")).to be(false)
  end

  it "treats a section as complete once its clauses are loaded or when it has none" do
    expect(tree.complete?("s:paper.md#intro")).to be(false)
    expect(tree.complete?("s:note.txt#0")).to be(true)
    expect(tree.complete?("d:10")).to be(true)
  end
end
