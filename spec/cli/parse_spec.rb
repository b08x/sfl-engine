# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::CLI do
  describe ".parse" do
    it "raises UsageError for an unknown subcommand" do
      expect { described_class.parse(%w[bogus foo]) }.to raise_error(described_class::UsageError, /Unknown subcommand/)
    end

    it "raises UsageError when the input argument is missing" do
      expect do
        described_class.parse(["conversation"])
      end.to raise_error(described_class::UsageError, /requires an input/)
    end

    it "raises UsageError when the next token looks like a flag, not an input" do
      expect { described_class.parse(%w[conversation --resume]) }
        .to raise_error(described_class::UsageError, /requires an input/)
    end

    it "normalizes hyphenated subcommand names (knowledge-base -> knowledge_base)" do
      parsed = described_class.parse(%w[knowledge-base ./vault])
      expect(parsed[:command]).to eq(:knowledge_base)
      expect(parsed[:input]).to eq("./vault")
    end

    describe "conversation" do
      it "applies defaults with no flags" do
        parsed = described_class.parse(%w[conversation input.jsonl])
        expect(parsed[:command]).to eq(:conversation)
        expect(parsed[:input]).to eq("input.jsonl")
        expect(parsed[:options]).to eq(
          output_dir: "./output/latest", pass1_only: false, resume: false, store: false,
          narrative: false, topics: nil, allow_fallback: false, disable_tracing: false
        )
      end

      it "parses every conversation flag" do
        argv = %w[
          conversation
          input.jsonl
          --output-dir
          ./out
          --pass1-only
          --resume
          --store
          --narrative
          --topics
          5
          --allow-fallback
          --disable-tracing
]
        parsed = described_class.parse(argv)

        expect(parsed[:options]).to eq(
          output_dir: "./out", pass1_only: true, resume: true, store: true,
          narrative: true, topics: 5, allow_fallback: true, disable_tracing: true
        )
      end

      it "treats --topics 0 as HDP auto-discover (0, not nil)" do
        parsed = described_class.parse(%w[conversation input.jsonl --topics 0])
        expect(parsed[:options][:topics]).to eq(0)
      end
    end

    describe "documentation" do
      it "shares conversation's exact option surface" do
        parsed = described_class.parse(%w[documentation ./docs --store --narrative])
        expect(parsed[:options]).to eq(
          output_dir: "./output/latest", pass1_only: false, resume: false, store: true,
          narrative: true, topics: nil, allow_fallback: false, disable_tracing: false
        )
      end
    end

    describe "knowledge_base" do
      it "applies defaults with no flags" do
        parsed = described_class.parse(%w[knowledge-base ./vault])
        expect(parsed[:options]).to eq(
          output_dir: "./output/latest", store: false, images: false, vision_model: nil,
          resume: false, annotated: false, disable_tracing: false
        )
      end

      it "parses every knowledge-base flag" do
        argv = %w[
          knowledge-base
          ./vault
          --output-dir
          ./out
          --store
          --images
          --vision-model
          llava
          --resume
          --annotated
          --disable-tracing
]
        parsed = described_class.parse(argv)

        expect(parsed[:options]).to eq(
          output_dir: "./out", store: true, images: true, vision_model: "llava",
          resume: true, annotated: true, disable_tracing: true
        )
      end

      it "--no-images overrides an earlier --images" do
        parsed = described_class.parse(%w[knowledge-base ./vault --images --no-images])
        expect(parsed[:options][:images]).to be(false)
      end
    end

    describe "ingest" do
      it "applies defaults with no flags" do
        parsed = described_class.parse(%w[ingest ./inbox])
        expect(parsed[:command]).to eq(:ingest)
        expect(parsed[:input]).to eq("./inbox")
        expect(parsed[:options]).to eq(output_dir: "./output/latest", disable_tracing: false)
      end

      it "parses --output-dir and --disable-tracing" do
        parsed = described_class.parse(%w[ingest ./inbox --output-dir ./out --disable-tracing])
        expect(parsed[:options]).to eq(output_dir: "./out", disable_tracing: true)
      end
    end

    describe "context" do
      it "applies defaults with no flags" do
        parsed = described_class.parse(["context", "does it work?"])
        expect(parsed[:input]).to eq("does it work?")
        expect(parsed[:options]).to eq(output_dir: nil, limit: 10, filters: {}, disable_tracing: false)
      end

      it "parses --limit and --output-dir" do
        parsed = described_class.parse(%w[context query --limit 3 --output-dir ./out])

        expect(parsed[:options][:limit]).to eq(3)
        expect(parsed[:options][:output_dir]).to eq("./out")
      end

      it "parses every filter flag into options[:filters]" do
        argv = %w[
          context
          query
          --mood
          declarative
          --min-tenor
          0.2
          --max-tenor
          0.8
          --min-modality
          0.1
          --max-modality
          0.9
]
        parsed = described_class.parse(argv)

        expect(parsed[:options][:filters]).to eq(
          mood: "declarative", min_tenor: 0.2, max_tenor: 0.8, min_modality: 0.1, max_modality: 0.9
        )
      end
    end
  end
end
