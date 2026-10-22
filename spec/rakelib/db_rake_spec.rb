# frozen_string_literal: true

require "spec_helper"
require "rake"

# Fact 19: `rake db:purge_collection[legacy]` deletes the collection, its
# documents, sections and clauses, and prints the counts it deleted.
RSpec.describe "rake db:purge_collection" do # rubocop:disable RSpec/DescribeClass -- a rake task, not a class
  let(:db) { SFL::Store::StoreTestDb.db }
  let(:rake) { Rake::Application.new }
  let(:task) { rake["db:purge_collection"] }

  before do
    SFL::Store::StoreTestDb.clean!
    Rake.application = rake
    load File.expand_path("../../rakelib/db.rake", __dir__)
    allow(SFL::Boot).to receive(:call).with(require_llm: false, require_tracing: false)
      .and_return(SFL::Boot::Result.new(db:))
  end

  after { Rake.application = Rake::Application.new }

  it "purges the legacy collection and prints the counts" do
    collection_id = db[:collections].insert(name: "legacy")
    doc = db[:documents].insert(collection_id:, document_key: "chat")
    SFL::Store::PgSectionRepository.new(db).upsert(doc, "chat#turn-1", ordinal: 1, kind: "turn")
    db[:clauses].insert(external_id: "c1", text: "t", section_id: "chat#turn-1", sentence_index: 0, root_index: 0)

    expect { task.invoke("legacy") }
      .to output("purged collection=legacy collections=1 documents=1 sections=1 clauses=1\n").to_stdout
    expect([db[:collections].count, db[:documents].count, db[:sections].count, db[:clauses].count])
      .to eq([0, 0, 0, 0])
  end

  it "aborts with the error for an unknown collection" do
    expect { task.invoke("nope") }.to raise_error(SystemExit).and output(/no collection named "nope"/).to_stderr
  end

  it "aborts with usage when no name is given" do
    expect { task.invoke }.to raise_error(SystemExit).and output(/usage/).to_stderr
  end
end
