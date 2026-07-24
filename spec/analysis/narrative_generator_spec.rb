# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::NarrativeGenerator do
  let(:sections) do
    {
      overview: "An overview.",
      cast_and_roles: "The cast.",
      interpersonal_dynamics: "Dynamics.",
      conversational_arc: "The arc.",
      data_quality: "Quality notes.",
      takeaways: "Takeaways.",
    }
  end

  let(:analysis_result) do
    build_analysis_result(
      metadata: { conversation_id: "conv-1", turn_count: 1, low_confidence: false },
      turns: [build_turn(turn_id: 1, clauses: [build_annotated_clause])],
      insights: ["insight one"]
    )
  end

  describe "#initialize" do
    it "requires narrator: (raises ArgumentError when omitted, matching this app's DI-everywhere convention)" do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe "#generate" do
    it "builds a Core::Types::NarrativeReport from the digest and the narrator's sections" do
      narrator = -> (_text) { sections }
      digest = described_class::Digest.from_result(analysis_result)

      report = described_class.new(narrator:).generate(digest)

      expect(report).to be_a(SFL::Core::Types::NarrativeReport)
      expect(report.source).to eq("conv-1")
      expect(report.overview).to eq("An overview.")
      expect(report.takeaways).to eq("Takeaways.")
    end

    it "calls the injected narrator with the digest's #to_text output" do
      received_text = nil
      narrator = lambda { |text|
        received_text = text
        sections
      }
      digest = described_class::Digest.from_result(analysis_result)

      described_class.new(narrator:).generate(digest)

      expect(received_text).to eq(digest.to_text)
    end

    it "wraps a Dry::Struct::Error from a malformed/missing-section narrator into NarrativeError" do
      narrator = -> (_text) { sections.except(:takeaways) }
      digest = described_class::Digest.from_result(analysis_result)

      expect { described_class.new(narrator:).generate(digest) }
        .to raise_error(SFL::Analysis::NarrativeError, /missing or invalid sections/)
    end

    it "wraps any other narrator failure into NarrativeError" do
      narrator = -> (_text) { raise "boom" }
      digest = described_class::Digest.from_result(analysis_result)

      expect { described_class.new(narrator:).generate(digest) }
        .to raise_error(SFL::Analysis::NarrativeError, /Narrative generation failed: boom/)
    end
  end

  describe described_class::Digest do
    describe ".from_result" do
      it "builds a source-agnostic snapshot with string-keyed metadata and annotation_coverage merged in" do
        digest = described_class.from_result(analysis_result)

        expect(digest.metadata["conversation_id"]).to eq("conv-1")
        expect(digest.metadata["annotation_coverage"]).to include("total_clauses" => 1, "llm" => 1)
      end

      it "derives #source from metadata['conversation_id']" do
        digest = described_class.from_result(analysis_result)

        expect(digest.source).to eq("conv-1")
      end

      it "carries one turn row per AnalysisResult turn, with defaulted_count from untrusted clauses" do
        result = build_analysis_result(
          metadata: { conversation_id: "conv-2" },
          turns: [
            build_turn(
              turn_id: 1,
              clauses: [
                build_annotated_clause(annotation_source: "llm"),
                build_annotated_clause(id: "c2", annotation_source: "stub"),
]
            ),
          ]
        )

        digest = described_class.from_result(result)

        expect(digest.turns.first["clause_count"]).to eq(2)
        expect(digest.turns.first["defaulted_count"]).to eq(1)
      end

      it "includes a LOW CONFIDENCE WARNING in #to_text when metadata['low_confidence'] is true" do
        result = build_analysis_result(metadata: {
          conversation_id: "conv-3",
          low_confidence: true,
          clause_count: 2,
          low_confidence_threshold: 30,
        })

        digest = described_class.from_result(result)

        expect(digest.to_text).to include("LOW CONFIDENCE WARNING")
      end

      it "omits the LOW CONFIDENCE WARNING when metadata['low_confidence'] is false" do
        digest = described_class.from_result(analysis_result)

        expect(digest.to_text).not_to include("LOW CONFIDENCE WARNING")
      end
    end
  end
end
