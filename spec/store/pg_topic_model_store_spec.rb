# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::PgTopicModelStore do
  subject(:store) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:result) do
    {
      topics: [0, 0, 1, -1],
      topic_words: { 0 => %w[alpha beta], 1 => %w[gamma], -1 => [] },
      coverage: 0.75,
      attempts: 3,
    }
  end

  # StoreTestDb.clean! does not list topic_models, so this spec clears it itself.
  before { db.run("TRUNCATE topic_models RESTART IDENTITY") }

  it "creates the table with the contract columns and the document index (migration 022)" do
    columns = db.schema(:topic_models).to_h { |name, info| [name, info] }

    expect(columns.keys).to contain_exactly(:id, :collection_key, :document_key, :topics, :topic_words,
      :coverage, :attempts, :run_id, :created_at)
    expect(columns[:id]).to include(primary_key: true, db_type: "bigint")
    expect(columns[:collection_key]).to include(allow_null: false, db_type: "text")
    expect(columns[:topics]).to include(allow_null: false, db_type: "jsonb")
    expect(columns[:topic_words]).to include(allow_null: false, db_type: "jsonb")
    expect(columns[:coverage]).to include(allow_null: false, db_type: "double precision")
    expect(columns[:attempts]).to include(allow_null: false, db_type: "integer")
    expect(columns[:run_id]).to include(allow_null: true, db_type: "text")
    expect(columns[:created_at]).to include(allow_null: false, db_type: "timestamp with time zone")

    indexes = db.indexes(:topic_models).values.map { |info| [info[:columns], info[:unique]] }
    expect(indexes).to include([%i[collection_key document_key created_at], false])
  end

  it "round-trips topics, topic_words with Integer keys, coverage, attempts and run_id" do
    id = store.save(collection_key: "c", document_key: "d", result:, run_id: "run-1")

    expect(id).to be_a(Integer)
    expect(store.latest(collection_key: "c", document_key: "d")).to include(
      topics: [0, 0, 1, -1],
      topic_words: { 0 => %w[alpha beta], 1 => %w[gamma], -1 => [] },
      coverage: 0.75,
      attempts: 3,
      run_id: "run-1",
      created_at: a_kind_of(Time)
    )
  end

  it "keeps every fit, returns the newest as latest, and counts all of them" do
    store.save(collection_key: "c", document_key: "d", result:)
    second = store.save(collection_key: "c", document_key: "d", result: result.merge(attempts: 5))

    expect(store.latest(collection_key: "c", document_key: "d")).to include(attempts: 5)
    expect(store.count(collection_key: "c", document_key: "d")).to eq(2)
    expect(db[:topic_models].max(:id)).to eq(second)
  end

  it "returns nil from latest for an unknown document" do
    expect(store.latest(collection_key: "c", document_key: "missing")).to be_nil
    expect(store.count(collection_key: "c", document_key: "missing")).to eq(0)
  end

  it "raises Store::Error and writes no row when a result key is missing" do
    bad = result.except(:coverage)

    expect { store.save(collection_key: "c", document_key: "d", result: bad) }
      .to raise_error(SFL::Store::Error, /coverage/)
    expect(db[:topic_models].count).to eq(0)
  end

  it "raises Store::Error when a result value has the wrong type" do
    expect { store.save(collection_key: "c", document_key: "d", result: result.merge(attempts: "3")) }
      .to raise_error(SFL::Store::Error, /attempts/)
    expect(db[:topic_models].count).to eq(0)
  end

  it "round-trips a nil run_id as nil" do
    store.save(collection_key: "c", document_key: "d", result:, run_id: nil)

    expect(store.latest(collection_key: "c", document_key: "d")).to include(run_id: nil)
  end
end
