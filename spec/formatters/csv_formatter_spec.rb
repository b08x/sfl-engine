# frozen_string_literal: true

require "spec_helper"
require "csv"

RSpec.describe SFL::Formatters::CSVFormatter do
  subject(:parsed) { CSV.parse(described_class.new(result).render, headers: true) }

  let(:turn) do
    build_turn(
      turn_id: 1, speaker: "Alice", avg_tenor: 0.712, avg_modality: 0.501, dominant_mood: "declarative",
      process_types: { "material" => 2, "mental" => 1 }, participants: %w[Alice Bob], tenor_shift: 0.15,
      semantic_coherence_score: 0.88, message_text: "x" * 60,
      timestamp: Time.new(2024, 1, 1, 12, 0, 0)
    )
  end
  let(:result) { build_analysis_result(turns: [turn]) }

  it "emits the expected header row" do
    expect(parsed.headers).to eq(%w[
      turn_id
      speaker
      timestamp
      message_preview
      avg_tenor
      avg_modality
      dominant_mood
      process_counts
      participants
      tenor_shift
      semantic_coherence_score
    ])
  end

  it "emits one row per turn with rounded/truncated values" do
    row = parsed.first

    expect(row["turn_id"]).to eq("1")
    expect(row["speaker"]).to eq("Alice")
    expect(row["timestamp"]).to eq("2024-01-01 12:00")
    expect(row["message_preview"]).to eq("#{'x' * 50}...")
    expect(row["avg_tenor"]).to eq("0.71")
    expect(row["avg_modality"]).to eq("0.5")
    expect(row["process_counts"]).to eq("material:2 mental:1")
    expect(row["participants"]).to eq("Alice Bob")
    expect(row["tenor_shift"]).to eq("0.15")
    expect(row["semantic_coherence_score"]).to eq("0.88")
  end

  it "leaves tenor_shift/semantic_coherence_score blank when nil" do
    turn_without = build_turn(tenor_shift: nil, semantic_coherence_score: nil)
    row = CSV.parse(described_class.new(build_analysis_result(turns: [turn_without])).render, headers: true).first

    expect(row["tenor_shift"]).to eq("")
    expect(row["semantic_coherence_score"]).to eq("")
  end
end
