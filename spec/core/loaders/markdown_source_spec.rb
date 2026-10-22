# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::MarkdownSource do
  let(:path) { "spec/fixtures/loaders/sample.md" }
  let(:ref) { file_ref(path) }
  let(:prefix) { SFL::Core::Loaders::FileId.call(ref) }

  it "is a Loaders::Source" do
    expect(described_class.new(ref)).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields one Unit per heading-scoped section" do
    units = described_class.new(ref).units

    expect(units).to all(be_a(SFL::Core::Types::Unit))
    expect(units.map(&:heading)).to eq(["Introduction", "Usage", "Advanced Topics"])
  end

  it "derives section_id from the filename stem and heading slug" do
    unit = described_class.new(ref).units.first

    expect(unit.section_id).to eq("#{prefix}#introduction")
  end

  it "strips markdown structure down to clean prose" do
    unit = described_class.new(ref).units.first

    expect(unit.text).to include("This document introduces the main concepts")
    expect(unit.text).not_to include("#")
  end

  it "drops sections shorter than min_length" do
    units = described_class.new(ref, min_length: 10_000).units

    expect(units).to be_empty
  end

  it "carries heading_level and heading_slug in metadata" do
    unit = described_class.new(ref).units.first

    expect(unit.metadata["heading_level"]).to eq(1)
    expect(unit.metadata["heading_slug"]).to eq("introduction")
  end

  describe "nesting (fact 13)" do
    let(:path) { "spec/fixtures/loaders/nested.md" }

    it "makes a heading the parent of what follows until a heading of the same or a higher level" do
      parents = described_class.new(ref).units.to_h { |unit| [unit.section_id, unit.parent_section_id] }

      expect(parents).to eq(
        "#{prefix}#preamble" => nil,
        "#{prefix}#overview" => nil,
        "#{prefix}#scope" => "#{prefix}#overview",
        "#{prefix}#limits" => "#{prefix}#scope",
        "#{prefix}#audience" => "#{prefix}#overview",
        "#{prefix}#reference" => nil
      )
    end

    it "uses the file path as document_key and source_path" do
      unit = described_class.new(ref).units.first

      expect(unit).to have_attributes(document_key: File.expand_path(path), source_path: File.expand_path(path))
    end
  end
end
