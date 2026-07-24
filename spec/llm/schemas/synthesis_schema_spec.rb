# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::LLM::Schemas::SynthesisSchema do
  let(:schema) { JSON.parse(described_class.new.to_json).dig("schema", "properties") }

  it "requires answer as a string" do
    expect(schema.dig("answer", "type")).to eq("string")
  end

  it "constrains cited_clause_numbers to an array of plain integers" do
    expect(schema.dig("cited_clause_numbers", "type")).to eq("array")
    expect(schema.dig("cited_clause_numbers", "items", "type")).to eq("integer")
  end

  it "constrains confidence to 0.0-1.0" do
    expect(schema.dig("confidence", "minimum")).to eq(0.0)
    expect(schema.dig("confidence", "maximum")).to eq(1.0)
  end
end
