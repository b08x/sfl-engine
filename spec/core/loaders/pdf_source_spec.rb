# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::PdfSource do
  let(:path) { "spec/fixtures/loaders/sample.pdf" }

  it "is a Loaders::Source" do
    expect(described_class.new(path)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields at least one Unit with extracted prose" do
    units = described_class.new(path).units

    expect(units).not_to be_empty
    expect(units).to all(be_a(SFL::Core::Types::Unit))
    expect(units.first.text).to include("The committee approved the annual budget")
  end

  it "derives document_id from the filename stem and a page-anchored slug" do
    unit = described_class.new(path).units.first

    expect(unit.document_id).to start_with("sample#p1-")
  end

  it "drops chunks shorter than min_length" do
    units = described_class.new(path, min_length: 10_000).units

    expect(units).to be_empty
  end
end
