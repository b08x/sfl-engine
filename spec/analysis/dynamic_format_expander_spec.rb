# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Regression proof for the corrupted `output/steve01` expansion: the LLM's
# parse was accepted verbatim and written through JSON.dump with no
# unescaping, no markdown scrubbing and no validation, which put literal
# two-character `\n` sequences into every topic token and merged Steve's
# replies into turns labelled "User".
RSpec.describe SFL::Analysis::DynamicFormatExpander do
  subject(:result) { described_class.normalize_parsed({ turns: }, logger) }

  let(:logger) { SFL::Core::Ports::Null::Logger.new }

  def turn(name:, mes:, is_user: false, send_date: nil)
    described_class::DynamicConversationSignature::Turn.new(name:, mes:, is_user:, send_date:)
  end

  describe ".normalize_parsed" do
    context "with clean input" do
      let(:turns) do
        [
          turn(name: "User", mes: "Well think about it though.\nShe replied at 10:34.", is_user: true),
          turn(name: "Steve", mes: "### 1. The Temporal Gap\n\nYou edited at 1:36 AM.", send_date: "2026-08-20T01:36:00Z"),
        ]
      end

      it "passes the bodies through unchanged and reports no anomalies" do
        expect(result).to be_success

        normalized, anomalies = result.value!
        expect(normalized.map(&:mes)).to eq([
          "Well think about it though.\nShe replied at 10:34.",
          "### 1. The Temporal Gap\n\nYou edited at 1:36 AM.",
        ])
        expect(normalized.map(&:name)).to eq(%w[User Steve])
        expect(normalized.last.send_date).to eq("2026-08-20T01:36:00Z")
        expect(anomalies).to eq({ double_escaped_turns: 0, total_turns: 2 })
      end
    end

    context "when the model double-escaped its own JSON" do
      let(:turns) do
        [
          # Exactly the shape measured in output/steve01: literal two-character
          # `\n` sequences, a markdown hard-break backslash, a blockquote marker.
          turn(name: "User", mes: "Do you see the bug?\\n\\n> quoted evidence\\\\\\n\\nMore evidence.", is_user: true),
        ]
      end

      it "decodes the escapes, scrubs the markdown artifacts, and counts the violation" do
        expect(result).to be_success

        normalized, anomalies = result.value!
        body = normalized.first.mes
        expect(body).to eq("Do you see the bug?\n\nquoted evidence\n\nMore evidence.")
        expect(body.scan("\\n")).to be_empty
        expect(anomalies[:double_escaped_turns]).to eq(1)
      end

      it "logs the contract violation rather than repairing it silently" do
        spy_logger = instance_spy(SFL::Core::Ports::Null::Logger)

        described_class.normalize_parsed({ turns: }, spy_logger)

        expect(spy_logger).to have_received(:warn).with(/double-escaped/)
      end
    end

    context "when escaped and real newlines are mixed" do
      let(:turns) { [turn(name: "User", mes: "real\nnewline and literal\\n", is_user: true)] }

      it "fails instead of guessing which escapes are real" do
        expect(result).to be_failure
        expect(result.failure.first).to eq(:mixed_escape)
      end
    end

    context "when a turn body contains a foreign speaker's header" do
      let(:turns) do
        [
          turn(name: "Steve", mes: "## 🤖 Steve\n\nWait. Hold on."),
          turn(name: "User", mes: "She replied at 10:34 PM.\n\n## 🤖 Steve\n\nThat is a 9 hour gap.", is_user: true),
        ]
      end

      it "fails loudly and names the offending turn instead of silently relabelling it" do
        expect(result).to be_failure

        code, detail = result.failure
        expect(code).to eq(:speaker_attribution)
        expect(detail.size).to eq(1)
        expect(detail.first).to match(/turn 1 is attributed to "User".*header\(s\) for "Steve"/)
      end
    end

    context "with no turns at all" do
      let(:turns) { [] }

      it "fails rather than writing an empty JSONL" do
        expect(result).to be_failure
        expect(result.failure.first).to eq(:empty_parse)
      end
    end
  end

  describe ".expand_and_write" do
    let(:turns) do
      [turn(name: "User", mes: 'Do you see the bug?\n\nEvidence.', is_user: true)]
    end

    it "writes normalized JSONL whose bodies carry real newlines" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "steve-example001.md")
        File.write(src, "raw transcript")
        out_path = File.join(dir, "out.jsonl")
        allow(described_class).to receive(:llm_expand).and_return({ turns: })

        described_class.expand_and_write(src, dir, :lm, "steve-example001", out_path, logger)

        record = JSON.parse(File.read(out_path).lines.first)
        expect(record["mes"]).to eq("Do you see the bug?\n\nEvidence.")
        expect(JSON.parse(File.read(File.join(dir, "steve-example001-raw_parsed.json")))["anomalies"])
          .to eq({ "double_escaped_turns" => 1, "total_turns" => 1 })
      end
    end

    it "raises ContractViolation, naming the file, when speaker attribution is broken" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "steve-example001.md")
        File.write(src, "raw transcript")
        broken = [
          turn(name: "Steve", mes: "## Steve\n\nHold on."),
          turn(name: "User", mes: "Mine.\n\n## Steve\n\nAnd mine.", is_user: true),
        ]
        allow(described_class).to receive(:llm_expand).and_return({ turns: broken })

        expect do
          described_class.expand_and_write(src, dir, :lm, "steve-example001", File.join(dir, "out.jsonl"), logger)
        end.to raise_error(described_class::ContractViolation, /steve-example001\.md.*speaker_attribution.*turn 1/)
      end
    end
  end
end
