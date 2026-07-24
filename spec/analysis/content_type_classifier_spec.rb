# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::ContentTypeClassifier do
  subject(:classifier) { described_class.new }

  def build_section(text: "Some prose about the system.")
    SFL::Core::Types::Unit.new(document_id: "doc#1", text:, metadata: {})
  end

  describe "#classify" do
    it "returns :image when frontmatter content_type is image, ahead of every other check" do
      section = build_section(text: "AI responses may include mistakes.")

      result = classifier.classify(section:, clauses: [], frontmatter: { "content_type" => "image" })

      expect(result).to eq(:image)
    end

    it "returns :ai_generated when the text matches the AI disclaimer pattern" do
      section = build_section(text: "Note: AI responses may include mistakes. Please verify.")

      result = classifier.classify(section:, clauses: [], frontmatter: nil)

      expect(result).to eq(:ai_generated)
    end

    it "returns :draft when a frontmatter tag matches the draft tag map" do
      section = build_section

      result = classifier.classify(section:, clauses: [], frontmatter: { "tags" => ["WIP"] })

      expect(result).to eq(:draft)
    end

    it "returns :tutorial when a frontmatter tag matches the tutorial tag map" do
      section = build_section

      result = classifier.classify(section:, clauses: [], frontmatter: { "tags" => ["how-to"] })

      expect(result).to eq(:tutorial)
    end

    it "returns :technical_reference when a frontmatter tag matches the technical_reference tag map" do
      section = build_section

      result = classifier.classify(section:, clauses: [], frontmatter: { "tags" => ["API"] })

      expect(result).to eq(:technical_reference)
    end

    it "returns :research_note when a frontmatter tag matches the research_note tag map" do
      section = build_section

      result = classifier.classify(section:, clauses: [], frontmatter: { "tags" => ["Research"] })

      expect(result).to eq(:research_note)
    end

    it "returns :code_snippet when more than 25% of the text is inside backtick spans" do
      code = "`#{'x' * 90}`"
      section = build_section(text: "intro #{code}")

      result = classifier.classify(section:, clauses: [], frontmatter: nil)

      expect(result).to eq(:code_snippet)
    end

    it "does not classify as :code_snippet when code chars are below MIN_CODE_CHARS" do
      section = build_section(text: "intro `short` more filler text padding the ratio way down low")

      result = classifier.classify(section:, clauses: [], frontmatter: nil)

      expect(result).not_to eq(:code_snippet)
    end

    it "returns :index for a stub section (<=2 clauses, <250 chars)" do
      section = build_section(text: "Tiny section.")

      result = classifier.classify(section:, clauses: [build_annotated_clause], frontmatter: nil)

      expect(result).to eq(:index)
    end

    it "does not treat a short section with >2 clauses as a stub" do
      section = build_section(text: "Tiny section.")
      clauses = Array.new(3) { |i| build_annotated_clause(id: "c#{i}") }

      result = classifier.classify(section:, clauses:, frontmatter: nil)

      expect(result).not_to eq(:index)
    end

    describe "the SFL-signal tie-breaker (#from_sfl)" do
      it "returns :technical_reference when avg_modality > 0.7 and dominant mood is declarative" do
        section = build_section(text: "x" * 300)
        clauses = [
          build_annotated_clause(id: "c1", mood: "declarative", modality: 0.9),
          build_annotated_clause(id: "c2", mood: "declarative", modality: 0.8),
          build_annotated_clause(id: "c3", mood: "declarative", modality: 0.9),
        ]

        result = classifier.classify(section:, clauses:, frontmatter: nil)

        expect(result).to eq(:technical_reference)
      end

      it "returns :tutorial when dominant process is material and dominant mood is imperative" do
        section = build_section(text: "x" * 300)
        clauses = [
          build_annotated_clause(id: "c1", mood: "imperative", modality: 0.4, process_type: "material"),
          build_annotated_clause(id: "c2", mood: "imperative", modality: 0.4, process_type: "material"),
          build_annotated_clause(id: "c3", mood: "imperative", modality: 0.4, process_type: "material"),
        ]

        result = classifier.classify(section:, clauses:, frontmatter: nil)

        expect(result).to eq(:tutorial)
      end

      it "returns :research_note when the dominant process is mental" do
        section = build_section(text: "x" * 300)
        clauses = [
          build_annotated_clause(id: "c1", mood: "declarative", modality: 0.4, process_type: "mental"),
          build_annotated_clause(id: "c2", mood: "declarative", modality: 0.4, process_type: "mental"),
        ]

        result = classifier.classify(section:, clauses:, frontmatter: nil)

        expect(result).to eq(:research_note)
      end

      it "falls back to :research_note when no from_sfl branch matches and clauses are non-empty" do
        section = build_section(text: "x" * 300)
        clauses = [
          build_annotated_clause(id: "c1", mood: "declarative", modality: 0.4, process_type: "relational"),
          build_annotated_clause(id: "c2", mood: "declarative", modality: 0.4, process_type: "relational"),
          build_annotated_clause(id: "c3", mood: "declarative", modality: 0.4, process_type: "relational"),
        ]

        result = classifier.classify(section:, clauses:, frontmatter: nil)

        expect(result).to eq(:research_note)
      end

      it "falls back to :research_note when clauses are empty (from_sfl returns nil)" do
        section = build_section(text: "x" * 300)

        result = classifier.classify(section:, clauses: [], frontmatter: nil)

        expect(result).to eq(:research_note)
      end
    end
  end
end
