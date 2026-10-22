# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::Null::ModelCatalog do
  it "lists nothing and claims no providers" do
    catalog = described_class.new

    expect([catalog.name, catalog.fetch, catalog.providers([])]).to eq(["null", [], []])
  end
end
