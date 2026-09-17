# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::CanvasSource do
  let(:path) { "spec/fixtures/loaders/sample.canvas" }
  let(:ref) { file_ref(path) }

  it "is a Loaders::Source" do
    expect(described_class.new(ref)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields only text nodes long enough to pass min_length, skipping group/file/link nodes" do
    units = described_class.new(ref).units

    expect(units.size).to eq(1)
    expect(units.first.text).to eq("The committee approved the annual budget after extensive review.")
  end

  it "derives document_id from the filename stem and node id" do
    unit = described_class.new(ref).units.first

    expect(unit.document_id).to eq("sample#node-1")
  end

  it "emits every text node, including short ones, when skip_empty is false" do
    units = described_class.new(ref, skip_empty: false).units

    expect(units.map(&:text)).to include("ok")
  end
end
