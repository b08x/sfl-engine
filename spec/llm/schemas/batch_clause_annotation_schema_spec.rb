# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::LLM::Schemas::BatchClauseAnnotationSchema do
  let(:schema) { JSON.parse(described_class.new.to_json).dig("schema", "properties") }

  it "wraps annotations in an array of per-clause objects carrying an index" do
    annotation_props = schema.dig("annotations", "items", "properties")

    expect(annotation_props).to include("index")
    expect(annotation_props.dig("index", "type")).to eq("integer")
  end

  it "constrains each annotation's mood to ClassificationRegistry's canonical mood values" do
    annotation_props = schema.dig("annotations", "items", "properties")

    expect(annotation_props.dig("mood", "enum")).to eq(SFL::Core::ClassificationRegistry.canonical_values(:mood))
  end
end
