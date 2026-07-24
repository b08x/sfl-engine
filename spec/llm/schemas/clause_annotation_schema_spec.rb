# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::LLM::Schemas::ClauseAnnotationSchema do
  let(:schema) { JSON.parse(described_class.new.to_json).dig("schema", "properties") }

  it "constrains mood to ClassificationRegistry's canonical mood values" do
    expect(schema.dig("mood", "enum")).to eq(SFL::Core::ClassificationRegistry.canonical_values(:mood))
  end

  it "constrains theme_type to ClassificationRegistry's canonical theme_type values" do
    expect(schema.dig("theme_type", "enum")).to eq(SFL::Core::ClassificationRegistry.canonical_values(:theme_type))
  end

  it "constrains modality_weight and tenor to 0.0-1.0 (fixes F6/D9: contract rejection, not clamp01)" do
    expect(schema.dig("modality_weight", "minimum")).to eq(0.0)
    expect(schema.dig("modality_weight", "maximum")).to eq(1.0)
    expect(schema.dig("tenor", "minimum")).to eq(0.0)
    expect(schema.dig("tenor", "maximum")).to eq(1.0)
  end

  it "requires premises as an array of type/source/value/optional-weight objects" do
    premise_props = schema.dig("premises", "items", "properties")

    expect(premise_props.keys).to contain_exactly("type", "source", "value", "weight")
  end
end
