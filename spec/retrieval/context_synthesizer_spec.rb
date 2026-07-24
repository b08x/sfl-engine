# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Retrieval::ContextSynthesizer do
  # rubocop:disable Metrics/ParameterLists -- one flat RetrievalResult fixture builder; every
  # kwarg maps 1:1 to a real RetrievalResult attribute a context-synthesis example needs to vary.
  def build_row(
    clause_id:, text: "It works.", document_id: "doc-1", rrf_score: 0.5,
    mood: "declarative", tenor: 0.6, process_type: "material",
    modality_weight: 0.8, annotation_source: "llm"
  )
    SFL::Core::Types::RetrievalResult.new(
      clause_id:, text:, document_id:, rrf_score:, mood:, tenor:, process_type:,
      modality_weight:, annotation_source:
    )
  end
  # rubocop:enable Metrics/ParameterLists

  let(:retriever) { instance_double(SFL::Core::Ports::Retriever) }
  let(:synthesizer_double) { instance_double(SFL::LLM::Synthesizers::ContextSynthesizer) }

  describe "#initialize" do
    it "raises ArgumentError when given neither chat: nor an explicit synthesizer:" do
      expect { described_class.new(retriever:) }.to raise_error(ArgumentError, /chat:/)
    end
  end

  describe "#synthesize" do
    it "builds a RetrievalQuery from the filters Hash and passes it to the retriever" do
      allow(retriever).to receive(:retrieve).and_return([])
      instance = described_class.new(retriever:, synthesizer: synthesizer_double)

      instance.synthesize("does it work?", filters: { mood: "declarative" }, limit: 5)

      expect(retriever).to have_received(:retrieve) do |query|
        expect(query).to be_a(SFL::Core::Types::RetrievalQuery)
        expect(query.query).to eq("does it work?")
        expect(query.limit).to eq(5)
        expect(query.filters.mood).to eq("declarative")
      end
    end

    context "when retrieval returns no rows" do
      it "returns a SynthesisResult with a nil answer and zero retrieved_count" do
        allow(retriever).to receive(:retrieve).and_return([])
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?")

        expect(result).to be_a(SFL::Core::Types::SynthesisResult)
        expect(result.answer).to be_nil
        expect(result.retrieved_count).to eq(0)
        expect(result.clauses).to eq([])
      end
    end

    context "with citable rows (happy path)" do
      it "formats numbered evidence, calls the synthesizer, and maps cited numbers back to clause ids" do
        rows = [build_row(clause_id: "c-1", text: "It works."), build_row(clause_id: "c-2", text: "It fails.")]
        allow(retriever).to receive(:retrieve).and_return(rows)
        allow(synthesizer_double).to receive(:call)
          .and_return(answer: "It works.", cited_clause_numbers: [1], confidence: 0.9)
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?")

        expect(synthesizer_double).to have_received(:call) do |query:, evidence:|
          expect(query).to eq("does it work?")
          expect(evidence).to include("[1] It works.")
          expect(evidence).to include("[2] It fails.")
        end
        expect(result.answer).to eq("It works.")
        expect(result.cited_clause_ids).to eq(["c-1"])
        expect(result.retrieved_count).to eq(2)
        expect(result.confidence).to eq(0.9)
        expect(result.clauses.size).to eq(2)
      end

      it "drops out-of-range cited clause numbers rather than trusting them" do
        rows = [build_row(clause_id: "c-1")]
        allow(retriever).to receive(:retrieve).and_return(rows)
        allow(synthesizer_double).to receive(:call)
          .and_return(answer: "It works.", cited_clause_numbers: [1, 99, -1, 0], confidence: 0.5)
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?")

        expect(result.cited_clause_ids).to eq(["c-1"])
      end
    end

    context "when every retrieved row is fallback/stub-sourced (citable.empty?)" do
      it "returns the Data Quality preamble as the answer without calling the synthesizer" do
        rows = [
          build_row(clause_id: "c-1", annotation_source: "fallback"),
          build_row(clause_id: "c-2", annotation_source: "stub"),
        ]
        allow(retriever).to receive(:retrieve).and_return(rows)
        allow(synthesizer_double).to receive(:call)
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?")

        expect(synthesizer_double).not_to have_received(:call)
        expect(result.answer).to include("Data Quality: 2/2")
        expect(result.confidence).to be_nil
        expect(result.retrieved_count).to eq(2)
        expect(result.clauses.size).to eq(2)
      end

      it "includes fallback-sourced rows when include_fallback is true" do
        rows = [build_row(clause_id: "c-1", annotation_source: "fallback")]
        allow(retriever).to receive(:retrieve).and_return(rows)
        allow(synthesizer_double).to receive(:call)
          .and_return(answer: "It works.", cited_clause_numbers: [1], confidence: 0.4)
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?", include_fallback: true)

        expect(synthesizer_double).to have_received(:call)
        expect(result.cited_clause_ids).to eq(["c-1"])
      end
    end

    context "when the synthesizer's raw output fails SynthesisResult's own contract" do
      it "rescues the Dry::Struct::Error and returns evidence without an answer" do
        rows = [build_row(clause_id: "c-1")]
        allow(retriever).to receive(:retrieve).and_return(rows)
        allow(synthesizer_double).to receive(:call)
          .and_return(answer: "It works.", cited_clause_numbers: [1], confidence: "high")
        instance = described_class.new(retriever:, synthesizer: synthesizer_double)

        result = instance.synthesize("does it work?")

        expect(result.answer).to be_nil
        expect(result.confidence).to be_nil
        expect(result.retrieved_count).to eq(1)
        expect(result.clauses.size).to eq(1)
      end
    end
  end
end
