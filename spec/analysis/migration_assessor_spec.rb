# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::MigrationAssessor do
  subject(:assessor) { described_class.new }

  def assess(content_type:, quality_score:)
    assessor.assess(artifact_id: 1, title: "Title", source_file: "f.md", content_type:, quality_score:)
  end

  describe "#assess" do
    it "recommends :review for :ai_generated content regardless of quality_score, ahead of every other rule" do
      entry = assess(content_type: :ai_generated, quality_score: 0.99)

      expect(entry.action).to eq(:review)
      expect(entry.reason).to include("AI-generated")
    end

    it "recommends :review for :draft/:code_snippet/:image content, ahead of the quality-based rules" do
      %i[draft code_snippet image].each do |type|
        entry = assess(content_type: type, quality_score: 0.99)

        expect(entry.action).to eq(:review)
      end
    end

    it "recommends :archive when quality_score is below 0.35, even for a keep-eligible content_type" do
      entry = assess(content_type: :technical_reference, quality_score: 0.10)

      expect(entry.action).to eq(:archive)
      expect(entry.reason).to include("below archive threshold")
    end

    it "recommends :keep for :technical_reference/:tutorial content at or above 0.65 quality" do
      ref_entry = assess(content_type: :technical_reference, quality_score: 0.65)
      tut_entry = assess(content_type: :tutorial, quality_score: 0.9)

      expect(ref_entry.action).to eq(:keep)
      expect(tut_entry.action).to eq(:keep)
    end

    it "recommends :update when quality_score is at or above 0.50 but the content_type isn't keep-eligible" do
      entry = assess(content_type: :research_note, quality_score: 0.50)

      expect(entry.action).to eq(:update)
      expect(entry.reason).to include("Adequate quality")
    end

    it "recommends :update for a keep-eligible content_type below the keep threshold but at/above update" do
      entry = assess(content_type: :technical_reference, quality_score: 0.55)

      expect(entry.action).to eq(:update)
    end

    it "recommends :archive as the final fallback (quality below 0.50, not keep-eligible)" do
      entry = assess(content_type: :research_note, quality_score: 0.45)

      expect(entry.action).to eq(:archive)
      expect(entry.reason).to include("Low quality score")
    end

    it "returns a Core::Types::MigrationManifestEntry carrying the input identity fields through" do
      entry = assess(content_type: :research_note, quality_score: 0.45)

      expect(entry).to be_a(SFL::Core::Types::MigrationManifestEntry)
      expect(entry.artifact_id).to eq(1)
      expect(entry.title).to eq("Title")
      expect(entry.source_file).to eq("f.md")
      expect(entry.content_type).to eq(:research_note)
      expect(entry.quality_score).to eq(0.45)
    end
  end
end
