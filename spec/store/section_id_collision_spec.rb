# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# H1: files that share a basename must keep separate sections and clauses.
# Units come from the real loaders; each unit is stored the way
# Pipeline#persist stores it (clause replacement and registration in one
# SectionRegistry transaction), with one clause row per unit.
RSpec.describe "Section ids of files that share a basename" do # rubocop:disable RSpec/DescribeClass -- covers loaders, PgSectionRegistry and CollectionPurger together
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil) }
  let(:root) { Dir.mktmpdir }
  let(:body) { "This paragraph is long enough to pass the loader's minimum section length." }

  before { SFL::Store::StoreTestDb.clean! }
  after { FileUtils.rm_rf(root) }

  def write(relative, title)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# #{title}\n\n#{body}\n\n## Details\n\n#{body}\n")
    path
  end

  def ingest(collection, *paths)
    registry = SFL::Store::PgSectionRegistry.new(db, collection:, logger:)
    paths.flat_map { |path| SFL::Core::Loaders::MarkdownSource.new(SFL::Core::Refs::FileRefBuilder.call(path)).units }
      .each { |unit| store(registry, unit) }
  end

  def store(registry, unit)
    registry.transaction do
      db[:clauses].where(section_id: unit.section_id).delete
      db[:clauses].insert(external_id: "#{unit.document_key}|#{unit.section_id}", text: unit.text,
        section_id: unit.section_id, sentence_index: 0, root_index: 0)
      registry.register(unit, 1)
    end
  end

  def sections_of(path) = db[:sections].join(:documents, id: :document_id).where(document_key: path).select_map(:section_id)

  def clause_owners_of(path) = db[:clauses].where(section_id: sections_of(path)).select_map(:external_id).map { |id| id.split("|").first }

  def purge(name) = SFL::Store::CollectionPurger.new(db).purge(name)

  def expect_separate(first, second)
    expect(sections_of(first).size).to eq(2)
    expect(sections_of(second).size).to eq(2)
    expect(sections_of(first) & sections_of(second)).to eq([])
    expect(clause_owners_of(first)).to eq([first, first])
    expect(clause_owners_of(second)).to eq([second, second])
  end

  it "keeps two README.md files from different directories apart in one ingest" do
    a = write("a/README.md", "Alpha")
    b = write("b/README.md", "Beta")
    other = write("c/README.md", "Gamma")
    ingest("docs", a, b)
    ingest("other", other)

    expect_separate(a, b)
    purge("other")
    expect_separate(a, b)
    purge("docs")
    expect(db[:sections].count).to eq(0)
    expect(logger).not_to have_received(:warn)
  end

  it "keeps two README.md files ingested into two collections apart, and purging one leaves the other" do
    a = write("a/README.md", "Alpha")
    b = write("b/README.md", "Beta")
    ingest("alpha", a)
    ingest("beta", b)

    expect_separate(a, b)
    purge("alpha")
    expect(sections_of(a)).to eq([])
    expect(sections_of(b).size).to eq(2)
    expect(clause_owners_of(b)).to eq([b, b])
    expect(logger).not_to have_received(:warn)
  end

  it "keeps notes.md and notes.txt side by side apart" do
    md = write("d/notes.md", "Notes")
    txt = write("d/notes.txt", "Notes")
    other = write("e/notes.md", "Other")
    ingest("notes", md, txt)
    ingest("other", other)

    expect_separate(md, txt)
    purge("other")
    expect_separate(md, txt)
  end

  it "keeps a document's section ids when it is ingested again" do
    a = write("a/README.md", "Alpha")
    ingest("docs", a)
    before = sections_of(a).sort

    ingest("docs", a)

    expect(sections_of(a).sort).to eq(before)
    expect(db[:clauses].count).to eq(2)
    expect(logger).not_to have_received(:warn)
  end
end
