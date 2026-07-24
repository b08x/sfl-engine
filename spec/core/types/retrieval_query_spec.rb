# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::RetrievalQuery do
  it "requires only query text" do
    query = described_class.new(query: "what did the imperative clauses say")

    expect(query.query).to eq("what did the imperative clauses say")
  end

  it "defaults limit to 10" do
    query = described_class.new(query: "hello")

    expect(query.limit).to eq(10)
  end

  it "defaults filters to an empty (no-op) RetrievalFilters instance" do
    query = described_class.new(query: "hello")

    expect(query.filters).to eq(SFL::Core::Types::RetrievalFilters.new)
  end

  it "accepts an explicit limit and filters" do
    query = described_class.new(query: "hello", limit: 5, filters: { mood: "imperative" })

    expect(query.limit).to eq(5)
    expect(query.filters.mood).to eq("imperative")
  end

  it "raises on an unrecognized top-level key instead of silently ignoring it" do
    expect { described_class.new(query: "hello", typo_key: 1) }.to raise_error(Dry::Struct::Error)
  end

  it "round-trips through Wire.dump/Types::RetrievalQuery.new" do
    query = described_class.new(query: "hello", limit: 5, filters: { mood: "imperative" })

    dumped = SFL::Core::Wire.dump(query)
    reloaded = described_class.new(dumped)

    expect(reloaded).to eq(query)
  end
end
