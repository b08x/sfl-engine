# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::CanvasSource do
  let(:path) { "spec/fixtures/loaders/sample.canvas" }
  let(:ref) { file_ref(path) }
  let(:prefix) { SFL::Core::Loaders::FileId.call(ref) }

  it "is a Loaders::Source" do
    expect(described_class.new(ref)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields only text nodes long enough to pass min_length, skipping group/file/link nodes" do
    units = described_class.new(ref).units

    expect(units.size).to eq(1)
    expect(units.first.text).to eq("The committee approved the annual budget after extensive review.")
  end

  it "derives section_id from the filename stem and node id" do
    unit = described_class.new(ref).units.first

    expect(unit.section_id).to eq("#{prefix}#node-1")
  end

  it "emits every text node, including short ones, when skip_empty is false" do
    units = described_class.new(ref, skip_empty: false).units

    expect(units.map(&:text)).to include("ok")
  end

  it "leaves level-1 canvas nodes without a parent and keys them by file path (fact 13)" do
    units = described_class.new(ref, skip_empty: false).units

    expect(units.map(&:parent_section_id).uniq).to eq([nil])
    expect(units.map(&:document_key).uniq).to eq([File.expand_path(path)])
  end
end
