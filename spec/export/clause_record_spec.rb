# frozen_string_literal: true

require_relative "export_helper"

# Fact 42: the JSONL object's fields.
RSpec.describe SFL::Export::ClauseRecord do
  it "carries collection, document key, source path, section id and path, speaker, text and payloads" do
    record = ExportSpecSupport.records.find { |each| each.id == "b1" }

    expect(record.to_json_hash).to eq(
      collection: "papers", document_key: "paper.md", source_path: "/data/paper.md", section_id: "paper.md#background",
      section_path: "Intro > Background", speaker: nil, text: "Background one.",
      ideational: { process_type: "material" }, interpersonal: { mood: "declarative", tenor: 0.5 }
    )
  end
end
