# frozen_string_literal: true

require_relative "export_helper"

# Fact 42: one object per clause.
RSpec.describe SFL::Export::JsonlWriter do
  it "writes one JSON object per clause, matching the golden file" do
    output = ExportSpecSupport.write(described_class, ExportSpecSupport.records)

    expect(output).to eq(ExportSpecSupport.golden("papers.jsonl"))
    expect(output.lines.map { |line| JSON.parse(line).keys }.uniq).to eq(
      [%w[collection document_key source_path section_id section_path speaker text ideational interpersonal]]
    )
  end
end
