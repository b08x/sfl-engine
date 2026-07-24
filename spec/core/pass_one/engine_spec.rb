# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::PassOne::Engine do
  describe "with the real SpacySidecarParser" do
    subject(:engine) { described_class.new(parser:) }

    let(:parser) { SFL::Core::PassOne::SpacySidecarParser.new(model: "en_core_web_sm") }

    after { parser.close }

    # Characterization spec per Phase 0 (trackboi decision 2 / blueprint F1):
    # pins the head-index resolution contract the Python sidecar must
    # satisfy. The legacy PassOneEngine resolved a token's head by looking
    # up `local_idx[token.head.text]` -- a TEXT-keyed hash -- so on a
    # sentence with a repeated word, every duplicate's dependents resolved
    # to the FIRST occurrence of that word instead of the correct one. The
    # sidecar fixes this structurally by carrying spaCy's native positional
    # `token.i` (offset from `sent.start`) instead of a text lookup.
    it "resolves head_index positionally, not by matching head token text" do
      clauses = engine.process("The dog chased the cat.")
      tokens = clauses.first.tokens

      # both "the" tokens must NOT collapse to the same head_index
      the_tokens = tokens.select { |t| %w[the The].include?(t.text) }
      expect(the_tokens.map(&:head_index).uniq.size).to eq(2)

      # "cat"'s head ("chased") must resolve correctly even though
      # "chased" is not the first token in the sentence
      cat = tokens.find { |t| t.text == "cat" }
      expect(tokens[cat.head_index].text).to eq("chased")

      # neither "the" may be misclassified as ROOT via a text-match false positive
      expect(the_tokens.map(&:dep)).to all(eq("det"))
    end
  end

  describe "with a Null parser" do
    subject(:engine) { described_class.new(parser: SFL::Core::Ports::Null::SyntacticParser.new) }

    it "returns [] for nil or blank text without calling the parser" do
      expect(engine.process(nil)).to eq([])
      expect(engine.process("   ")).to eq([])
    end

    it "delegates non-blank text to the parser" do
      expect(engine.process("Some text.")).to eq([])
    end
  end

  describe "error translation" do
    subject(:engine) { described_class.new(parser: failing_parser) }

    let(:failing_parser) { instance_double(SFL::Core::PassOne::SpacySidecarParser) }

    it "wraps an unexpected parser failure in SFL::Core::PassOne::Error" do
      allow(failing_parser).to receive(:parse).and_raise(StandardError, "boom")

      expect { engine.process("text") }.to raise_error(SFL::Core::PassOne::Error, /boom/)
    end

    it "does not re-wrap an already-domain SidecarError" do
      allow(failing_parser).to receive(:parse).and_raise(SFL::Core::PassOne::SidecarError, "sidecar down")

      expect { engine.process("text") }.to raise_error(SFL::Core::PassOne::SidecarError, "sidecar down")
    end
  end
end
