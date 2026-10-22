# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::ModelCatalog do
  let(:adapter) { Class.new { include SFL::Core::Ports::ModelCatalog }.new }

  it "requires #name, #providers and #fetch from an adapter" do
    expect { adapter.name }.to raise_error(NotImplementedError)
    expect { adapter.providers([]) }.to raise_error(NotImplementedError)
    expect { adapter.fetch }.to raise_error(NotImplementedError)
  end

  it "turns an entry into a row hash" do
    entry = described_class::Entry.new(provider: "p", model_id: "m", name: "M", context_window: 1, capabilities: [], pricing: {})

    expect(entry.to_row).to eq(provider: "p", model_id: "m", name: "M", context_window: 1, capabilities: [], pricing: {})
  end
end
