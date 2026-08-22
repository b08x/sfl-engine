# frozen_string_literal: true

require "spec_helper"
require "dspy"

# There was no coverage for run_conversation at all, which is how a run that
# annotated 0 of 134 clauses could exit 0 with a green suite. The contract
# asserted here: a conversation whose Pass 2 annotations fell back to
# placeholder values still writes its artifacts (a degraded report is useful
# for debugging Pass 1) AND reports a non-zero exit code, so nothing reading
# the exit code mistakes placeholders for findings.
RSpec.describe SFL::CLI do
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config: instance_double(SFL::LLM::Config),
      lm_factory: instance_double(SFL::LLM::LMFactory), embedder: instance_double(SFL::LLM::Embedder),
      pass1_command: nil, spacy_model: "en_core_web_sm"
    )
  end
  let(:engine) { instance_double(SFL::Analysis::Engine) }
  let(:options) do
    {
      output_dir: "./out",
      pass1_only: false,
      resume: false,
      store: false,
      narrative: false,
      topics: nil,
      allow_fallback: false,
      disable_tracing: true,
    }
  end

  def clause(annotation_source)
    interpersonal = SFL::Core::Types::InterpersonalPayload.new(
      clause_id: "syn-1", mood: "declarative", modality_weight: 0.5, tenor: 0.5,
      speaker_attitude: nil, reasoning: nil, annotation_source:
    )
    instance_double(SFL::Core::Types::AnnotatedClause, interpersonal:)
  end

  def result_with(*sources)
    turn = instance_double(SFL::Core::Types::ConversationTurn, clauses: sources.map { |s| clause(s) })
    instance_double(SFL::Core::Types::AnalysisResult, metadata: { interrupted: false }, turns: [turn])
  end

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive(:call).and_return(boot_result)
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(engine)
    allow(SFL::Analysis::ConversationSource).to receive(:new)
      .and_return(instance_double(SFL::Analysis::ConversationSource))
    allow(SFL::Formatters::ReportWriter).to receive(:write).and_return({ json: "./out/a.json" })
    allow(described_class).to receive(:gather_conversation_files)
      .and_return([{ path: "a.jsonl", source_type: "chat_native", label: "a" }])
    allow($stdout).to receive(:puts)
  end

  describe ".run_conversation" do
    it "returns 0 when every clause carries a trusted annotation" do
      allow(engine).to receive(:analyze).and_return(result_with("llm", "llm"))

      expect(described_class.run_conversation("a.jsonl", options)).to eq(0)
    end

    it "returns 1 when ANY clause fell back — one placeholder is already a degraded report" do
      allow(engine).to receive(:analyze).and_return(result_with("llm", "fallback"))

      expect { expect(described_class.run_conversation("a.jsonl", options)).to eq(1) }
        .to output(%r{1/2 clauses \(50.0%\) carry fallback}).to_stderr
    end

    it "still writes the artifacts for a fully-defaulted run before failing it" do
      allow(engine).to receive(:analyze).and_return(result_with("fallback", "fallback"))

      status = nil
      expect { status = described_class.run_conversation("a.jsonl", options) }.to output.to_stderr

      expect(status).to eq(1)
      expect(SFL::Formatters::ReportWriter).to have_received(:write).with(anything, "./out")
    end

    it "names the degraded file in the aggregated failure summary of a multi-file run" do
      allow(described_class).to receive(:gather_conversation_files).and_return(
        [
          { path: "a.jsonl", source_type: "chat_native", label: "a" },
          { path: "b.jsonl", source_type: "chat_native", label: "b" },
]
      )
      allow(engine).to receive(:analyze).and_return(result_with("fallback"), result_with("llm"))

      expect { expect(described_class.run_conversation("./dir", options)).to eq(1) }
        .to output(%r{1/2 conversations failed: a \(1 fallback clauses\)}).to_stderr
    end

    it "does not fail a --pass1-only run, whose stub values are what the operator asked for" do
      allow(engine).to receive(:analyze).and_return(result_with("stub", "stub"))

      expect { expect(described_class.run_conversation("a.jsonl", options.merge(pass1_only: true))).to eq(0) }
        .to output.to_stderr
    end

    it "honors --allow-fallback as the explicit opt-out, but only when asked" do
      allow(engine).to receive(:analyze).and_return(result_with("fallback"))

      expect { expect(described_class.run_conversation("a.jsonl", options.merge(allow_fallback: true))).to eq(0) }
        .to output.to_stderr
    end
  end

  describe ".run" do
    it "propagates run_conversation's non-zero status as the process exit code" do
      allow(described_class).to receive(:run_conversation).and_return(1)

      expect(described_class.run(%w[conversation a.jsonl])).to eq(1)
    end
  end
end
