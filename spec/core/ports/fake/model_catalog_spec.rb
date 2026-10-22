# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Fake::ModelCatalog do
  let(:entry) do
    SFL::Core::Ports::ModelCatalog::Entry.new(provider: "p", model_id: "m", name: nil, context_window: nil,
      capabilities: [], pricing: {})
  end

  it "returns its entries and claims their providers" do
    catalog = described_class.new(name: "fake", entries: [entry])

    expect([catalog.name, catalog.fetch, catalog.providers([entry])]).to eq(["fake", [entry], ["p"]])
  end

  it "claims the given providers and raises the given error" do
    catalog = described_class.new(name: "fake", providers: ["q"], error: IOError.new("down"))

    expect(catalog.providers([entry])).to eq(["q"])
    expect { catalog.fetch }.to raise_error(IOError, "down")
  end
end
