# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::MarkdownSource do
  let(:path) { "spec/fixtures/loaders/sample.md" }

  it "is a Loaders::Source" do
    expect(described_class.new(path)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields one Unit per heading-scoped section" do
    units = described_class.new(path).units

    expect(units).to all(be_a(SFL::Core::Types::Unit))
    expect(units.map(&:heading)).to eq(["Introduction", "Usage", "Advanced Topics"])
  end

  it "derives document_id from the filename stem and heading slug" do
    unit = described_class.new(path).units.first

    expect(unit.document_id).to eq("sample#introduction")
  end

  it "strips markdown structure down to clean prose" do
    unit = described_class.new(path).units.first

    expect(unit.text).to include("This document introduces the main concepts")
    expect(unit.text).not_to include("#")
  end

  it "drops sections shorter than min_length" do
    units = described_class.new(path, min_length: 10_000).units

    expect(units).to be_empty
  end

  it "carries heading_level and heading_slug in metadata" do
    unit = described_class.new(path).units.first

    expect(unit.metadata["heading_level"]).to eq(1)
    expect(unit.metadata["heading_slug"]).to eq("introduction")
  end
end
