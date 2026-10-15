# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::Analysis::NarrativeGenerator::Digest do
  # A two-turn result with a KEY MOMENT and a tenor shift, so the round trip
  # covers every field the digest text reads.
  let(:result) do
    turns = [
      build_turn(turn_id: 1, speaker: "Alice", avg_tenor: 0.62, avg_modality: 0.8, dominant_mood: "declarative",
        clauses: [build_annotated_clause(id: "c1")], message_text: "I think the deadline is Friday."),
      build_turn(turn_id: 2, speaker: "Bob", avg_tenor: 0.31, avg_modality: 0.4, dominant_mood: "interrogative",
        tenor_shift: 0.4, clauses: [build_annotated_clause(id: "c2")], message_text: "Why would we move it?"),
    ]
    build_analysis_result(
      metadata: {
        conversation_id: "conv-json", source_file: "conv-json.jsonl", turn_count: 2, speakers: %w[Alice Bob],
        analyzed_at: "2026-10-15T10:00:00+00:00", topics_enabled: false, interrupted: false, total: 2,
      },
      turns:,
      speaker_profiles: {},
      correlations: { "tenor_modality" => 0.5 },
      insights: ["Bob reverses the plan."],
      key_moments: [SFL::Core::Types::KeyMoment.new(type: "tenor_shift", turn_id: 2, magnitude: 0.4, description: "reversal")]
    )
  end

  let(:json) { JSON.parse(SFL::Formatters::JSONFormatter.new(result).render) }

  describe ".from_json" do
    it "round-trips an engine report to the same digest text as from_result (the equivalence contract)" do
      expect(described_class.from_json(json).to_text).to eq(described_class.from_result(result).to_text)
    end

    it "reads the conversation id and turn count under the canonical keys" do
      digest = described_class.from_json(json)

      expect(digest.source).to eq("conv-json")
      expect(digest.metadata).to include("conversation_id" => "conv-json", "turn_count" => 2)
    end

    it "accepts a documentation report whose keys use the document vocabulary" do
      doc_metadata = {
        "id_label" => "document_id", "unit_label" => "Section", "actor_label" => "Section",
        "actors_list_label" => "Headings", "document_id" => "doc-7", "section_count" => 2,
        "headings" => %w[A B]
      }
      doc_json = json.merge("metadata" => doc_metadata, "section_profiles" => {})

      digest = described_class.from_json(doc_json)

      expect(digest.metadata).to include("conversation_id" => "doc-7", "turn_count" => 2, "speakers" => %w[A B])
      expect(digest.metadata).not_to have_key("document_id")
    end

    it "rejects a report that predates the turns array, pointing the operator at a re-run" do
      expect { described_class.from_json(json.except("turns")) }
        .to raise_error(SFL::Analysis::NarrativeError, /predates narrative support/)
    end

    it "rejects a turn row missing a required key" do
      broken = json.merge("turns" => json["turns"].map { |row| row.except("avg_tenor") })

      expect { described_class.from_json(broken) }
        .to raise_error(SFL::Analysis::NarrativeError, /missing required key: avg_tenor/)
    end
  end
end
