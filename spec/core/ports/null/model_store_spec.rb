# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::ModelStore do
  it "keeps nothing" do
    store = described_class.new

    expect(store.sync([], providers: ["p"])).to eq(upserted: 0, unavailable: 0)
    expect(store.assign(:embedding, provider: "p", model_id: "m")).to be_nil
    expect([store.list, store.assignments]).to eq([[], {}])
  end
end
