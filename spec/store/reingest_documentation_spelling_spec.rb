# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# Fact 17 for `sfl-analyze documentation --store --collection C`: the CLI builds
# the document's ref with FileRefBuilder from the raw input, so a relative path,
# a ./relative path and an absolute path to the same file must all key one
# document, replace its sections and clauses, and advance its updated_at.
# The units are stored the way Pipeline#persist stores them (see
# spec/store/reingest_path_spelling_spec.rb).
RSpec.describe "Documentation re-store under another spelling of the path" do # rubocop:disable RSpec/DescribeClass -- covers FileRefBuilder, loaders and PgSectionRegistry together
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil) }
  let(:root) { Dir.mktmpdir }
  let(:path) { File.join(root, "notes.md") }
  let(:body) { "This paragraph is long enough to pass the loader's minimum section length." }

  before do
    SFL::Store::StoreTestDb.clean!
    File.write(path, "# Notes\n\n#{body}\n\n## Details\n\n#{body}\n")
  end

  after { FileUtils.rm_rf(root) }

  def store_document(spelling)
    ref = SFL::Core::Refs::FileRefBuilder.call(spelling)
    registry = SFL::Store::PgSectionRegistry.new(db, collection: "docs", logger:)
    SFL::Core::Loaders::MarkdownSource.new(ref).units.each do |unit|
      registry.transaction do
        db[:clauses].where(section_id: unit.section_id).delete
        db[:clauses].insert(external_id: "#{unit.document_key}|#{unit.section_id}", text: unit.text,
          section_id: unit.section_id, sentence_index: 0, root_index: 0)
        registry.register(unit, 1)
      end
    end
  end

  it "keeps one document with the same clauses and an advanced updated_at" do
    relative = Pathname(path).relative_path_from(Dir.pwd).to_s

    store_document(relative)
    clause_count = db[:clauses].count
    sections = db[:sections].select_order_map(:section_id)
    db[:documents].update(updated_at: Time.now - 3600)
    stale = db[:documents].get(:updated_at)

    store_document("./#{relative}")
    store_document(path)

    expect(db[:documents].select_map(:document_key)).to eq([File.expand_path(path)])
    expect(db[:clauses].count).to eq(clause_count)
    expect(clause_count).to eq(2)
    expect(db[:sections].select_order_map(:section_id)).to eq(sections)
    expect(db[:documents].get(:updated_at)).to be > stale
    expect(logger).not_to have_received(:warn)
  end
end
