# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::CsvSource do
  subject(:source) do
    described_class.new(path, text_column: "text", speaker_column: "speaker", document_id_column: "id")
  end

  let(:path) { "spec/fixtures/loaders/sample.csv" }

  it "is a Loaders::Source" do
    expect(source).to be_a(SFL::Core::Loaders::Source)
  end

  it "yields one Unit per non-blank row" do
    units = source.units

    expect(units.map(&:document_id)).to eq(%w[row-1 row-3])
    expect(units.map(&:speaker)).to eq(%w[Alice Carol])
  end

  it "skips rows with a blank text_column value" do
    units = source.units

    expect(units.map(&:text)).not_to include("")
  end

  it "includes blank rows when skip_empty is false" do
    units = described_class.new(
      path, text_column: "text", document_id_column: "id", skip_empty: false
    ).units

    expect(units.map(&:document_id)).to eq(%w[row-1 row-2 row-3])
  end

  it "falls back to a file_id/row-index document_id when document_id_column is absent" do
    units = described_class.new(path, text_column: "text", file_id: "sample").units

    expect(units.first.document_id).to eq("sample#row-0")
  end

  it "carries the full row Hash in metadata" do
    unit = source.units.first

    expect(unit.metadata["row"]).to include("id" => "row-1", "speaker" => "Alice")
  end
end
