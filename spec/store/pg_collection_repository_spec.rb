# frozen_string_literal: true

require "spec_helper"

# Fact 10: names are trimmed, keep their case, are unique ignoring case, and an
# empty name is rejected.
RSpec.describe SFL::Store::PgCollectionRepository do
  subject(:repo) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }

  before { SFL::Store::StoreTestDb.clean! }

  it "creates a trimmed collection that keeps its case" do
    expect(repo.find_or_create("  Field Notes ")[:name]).to eq("Field Notes")
  end

  it "finds the existing collection when the name differs only in case" do
    first = repo.find_or_create("Papers")

    expect(repo.find_or_create("PAPERS")[:id]).to eq(first[:id])
    expect(db[:collections].count).to eq(1)
  end

  it "rejects an empty name" do
    expect { repo.find_or_create(" ") }.to raise_error(SFL::Core::CollectionName::Error)
  end

  it "returns the existing row when a concurrent insert wins the unique index" do
    existing = repo.find_or_create("Race")
    racing = described_class.new(db)
    allow(racing).to receive(:find).and_return(nil, existing)

    expect(racing.find_or_create("race")[:id]).to eq(existing[:id])
  end

  it "lists collections by name ignoring case" do
    %w[beta Alpha].each { |name| repo.find_or_create(name) }

    expect(repo.list.map { |row| row[:name] }).to eq(%w[Alpha beta])
  end
end
