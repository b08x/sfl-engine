# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# Fact 17: re-ingesting a document into the same collection under another
# spelling of its path (relative, ./relative, absolute) replaces its sections
# and clauses and updates the document's updated_at. The Orchestrator walks
# the real filesystem; the knowledge-base dispatch stores each unit the way
# Pipeline#persist does (see spec/store/section_id_collision_spec.rb).
RSpec.describe "Re-ingest under another spelling of the path" do # rubocop:disable RSpec/DescribeClass -- covers Orchestrator, loaders and PgSectionRegistry together
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:logger) { instance_double(SFL::Core::Ports::Logger, warn: nil) }
  let(:root) { Dir.mktmpdir }
  let(:body) { "This paragraph is long enough to pass the loader's minimum section length." }
  let(:kb_source) { instance_double(SFL::Analysis::KnowledgeBaseSource) }
  let(:orchestrator) do
    SFL::Ingest::Orchestrator.new(
      conversation_engine: instance_double(SFL::Analysis::Engine), kb_source:,
      classifier: SFL::Core::Ports::Fake::Classifier.new(results: {}),
      loader_drafter: instance_double(SFL::Ingest::LoaderDrafter),
      review_repo: SFL::Store::PgIngestReviewRepository.new(db), store: true
    )
  end

  before do
    SFL::Store::StoreTestDb.clean!
    File.write(File.join(root, "notes.md"), "# Notes\n\n#{body}\n\n## Details\n\n#{body}\n")
    allow(kb_source).to receive(:analyze) { |ref, **| store_units(ref) }
  end

  after { FileUtils.rm_rf(root) }

  def store_units(ref)
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

  def ingest(spelling) = orchestrator.run(spelling)

  def relative_root = Pathname(root).relative_path_from(Dir.pwd).to_s

  it "replaces the document's sections and clauses and advances updated_at" do
    ingest(relative_root)
    clause_count = db[:clauses].count
    sections = db[:sections].select_order_map(:section_id)
    db[:documents].update(updated_at: Time.now - 3600)
    stale = db[:documents].get(:updated_at)

    ingest("./#{relative_root}")
    ingest(root)

    expect(db[:documents].select_map(:document_key)).to eq([File.join(root, "notes.md")])
    expect(db[:clauses].count).to eq(clause_count)
    expect(clause_count).to eq(2)
    expect(db[:sections].select_order_map(:section_id)).to eq(sections)
    expect(db[:documents].get(:updated_at)).to be > stale
    expect(logger).not_to have_received(:warn)
  end
end
