# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::Formatters::JSONFormatter do
  describe "PREVIEW_LENGTH" do
    it "is the same constant NarrativeGenerator::Digest uses, not a redeclared literal" do
      expect(described_class::PREVIEW_LENGTH).to equal(SFL::Analysis::NarrativeGenerator::Digest::PREVIEW_LENGTH)
    end
  end

  describe "#render" do
    subject(:parsed) { JSON.parse(described_class.new(result).render, symbolize_names: true) }

    let(:traced_clause) do
      clause = build_annotated_clause(id: "traced-1", annotation_source: "llm")
      clause.new(interpersonal: clause.interpersonal.new(reasoning_trace: build_reasoning_trace))
    end
    let(:untraced_clause) { build_annotated_clause(id: "untraced-1", annotation_source: "fallback") }
    let(:turn) do
      build_turn(
        turn_id: 1, speaker: "Alice", clauses: [traced_clause, untraced_clause],
        timestamp: Time.new(2024, 1, 1, 12, 0, 0)
      )
    end
    let(:metadata) { { conversation_id: "conv-1", turn_count: 1, speakers: ["Alice"] } }
    let(:result) do
      build_analysis_result(
        metadata:, turns: [turn], speaker_profiles: { "Alice" => build_speaker_profile },
        key_moments: [build_key_moment]
      )
    end

    def build_speaker_profile
      SFL::Core::Types::SpeakerProfile.new(
        speaker_name: "Alice", turn_count: 1, avg_tenor: 0.6, tenor_range: [0.5, 0.7], tenor_variance: 0.01,
        avg_modality: 0.5, mood_distribution: { "declarative" => 1 }, dominant_processes: { "material" => 1 }
      )
    end

    def build_key_moment
      SFL::Core::Types::KeyMoment.new(turn_id: 1, type: "tenor_shift", magnitude: 0.3, description: "shift")
    end

    it "renders valid JSON with the conversation-domain keys unchanged (no unit_label/actor_label set)" do
      expect(parsed[:metadata]).to include(conversation_id: "conv-1", turn_count: 1, speakers: ["Alice"])
      expect(parsed).to have_key(:speaker_profiles)
    end

    it "includes annotation_coverage in metadata" do
      expect(parsed[:metadata][:annotation_coverage]).to include(total_clauses: 2, llm: 1, fallback: 1)
    end

    it "truncates message_text to PREVIEW_LENGTH in each turn's preview" do
      expect(parsed[:turns].first[:preview]).to eq(turn.message_text[0, described_class::PREVIEW_LENGTH])
    end

    it "serializes reasoning_trace only for clauses that have one, with Time stringified" do
      clauses = parsed[:turns].first[:clauses]
      traced = clauses.find { |c| c[:id] == traced_clause.id }
      untraced = clauses.find { |c| c[:id] == untraced_clause.id }

      expect(traced[:reasoning_trace][:inference_rule]).to eq("modal_verb_strength")
      expect(traced[:reasoning_trace][:generated_at]).to be_a(String)
      expect(untraced[:reasoning_trace]).to be_nil
    end

    it "renames metadata/profiles keys per unit_label/actor_label/id_label/actors_list_label" do
      doc_metadata = metadata.merge(
        unit_label: "Section", actor_label: "heading", actors_list_label: "Headings", id_label: "document_id"
      )
      doc_result = build_analysis_result(metadata: doc_metadata, turns: [turn],
        speaker_profiles: { "Alice" => build_speaker_profile })

      doc_parsed = JSON.parse(described_class.new(doc_result).render, symbolize_names: true)

      expect(doc_parsed[:metadata]).to include(document_id: "conv-1", section_count: 1, headings: ["Alice"])
      expect(doc_parsed).to have_key(:heading_profiles)
      expect(doc_parsed).not_to have_key(:speaker_profiles)
    end
  end
end
