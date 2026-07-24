# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::JsonSource do
  shared_examples "a record source" do |path|
    subject(:source) do
      described_class.new(path, text_key: :text, speaker_key: :speaker, document_id_key: :id)
    end

    it "is a Loaders::Source" do
      expect(source).to be_a(SFL::Core::Loaders::Source)
    end

    it "yields one Unit per non-blank record, skipping blank text" do
      units = source.units

      expect(units.map(&:document_id)).to eq(%w[rec-1 rec-3])
      expect(units.map(&:speaker)).to eq(%w[Alice Carol])
    end

    it "falls back to a file_id/row-index document_id when document_id_key is absent" do
      units = described_class.new(path, text_key: :text, file_id: "sample").units

      expect(units.first.document_id).to eq("sample#row-0")
    end

    it "carries the full record Hash in metadata" do
      unit = source.units.first

      expect(unit.metadata["record"]).to include(id: "rec-1", speaker: "Alice")
    end
  end

  describe "with a .json array file" do
    it_behaves_like "a record source", "spec/fixtures/loaders/sample.json"
  end

  describe "with a .jsonl file" do
    it_behaves_like "a record source", "spec/fixtures/loaders/sample.jsonl"
  end
end
