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
      db: instance_double(Sequel::Database),
      llm_config: instance_double(SFL::LLM::Config, header: { "pass_two_annotation" => { "provider" => "openrouter", "model" => "m", "source" => "db" } }),
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
      .and_return([{ path: "spec/fixtures/inputs/sample.jsonl", source_type: "chat_native", label: "a" }])
    allow($stdout).to receive(:puts)
  end

  describe ".build_conversation_engine" do
    it "passes the Boot logger to Analysis::Engine" do
      boot_logger = instance_double(SFL::Core::Ports::StderrLogger)
      allow(SFL::Boot).to receive(:logger).and_return(boot_logger)
      allow(described_class).to receive(:build_pipeline).and_return(instance_double(SFL::Core::Pipeline))

      described_class.build_conversation_engine(boot_result, options, instance_double(SFL::CLI::StopFlag, stopped?: false))

      expect(SFL::Analysis::Engine).to have_received(:new).with(hash_including(logger: boot_logger))
    end
  end

  describe ".run_conversation" do
    it "writes a stored annotation run to the runs table and finishes it (fact 21)" do
      run_log = SFL::Core::Ports::Fake::RunLog.new
      allow(SFL::Store::PgRunRepository).to receive(:new).with(boot_result.db).and_return(run_log)
      allow(SFL::Boot).to receive(:run_id).and_return("run-3")
      allow(Thread).to receive(:new).and_return(instance_double(Thread, kill: nil))
      allow(engine).to receive(:analyze).and_return(result_with("llm"))

      described_class.run_conversation("a.jsonl", options.merge(store: true, collection: "chats"))

      expect(run_log.rows["run-3"]).to include(kind: "annotate", collection: "chats", status: "finished")
    end

    it "records the effective model per task in the run header (fact 65)" do
      run_log = SFL::Core::Ports::Fake::RunLog.new
      allow(SFL::Store::PgRunRepository).to receive(:new).with(boot_result.db).and_return(run_log)
      allow(SFL::Boot).to receive(:run_id).and_return("run-4")
      allow(Thread).to receive(:new).and_return(instance_double(Thread, kill: nil))
      allow(engine).to receive(:analyze).and_return(result_with("llm"))

      described_class.run_conversation("a.jsonl", options.merge(store: true, collection: "chats"))

      expect(run_log.rows["run-4"][:models])
        .to eq("pass_two_annotation" => { "provider" => "openrouter", "model" => "m", "source" => "db" })
    end

    it "returns 0 when every clause carries a trusted annotation" do
      allow(engine).to receive(:analyze).and_return(result_with("llm", "llm"))

      expect(described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options)).to eq(0)
    end

    it "returns 1 when ANY clause fell back — one placeholder is already a degraded report" do
      allow(engine).to receive(:analyze).and_return(result_with("llm", "fallback"))

      expect { expect(described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options)).to eq(1) }
        .to output(%r{1/2 clauses \(50.0%\) carry fallback}).to_stderr
    end

    it "still writes the artifacts for a fully-defaulted run before failing it" do
      allow(engine).to receive(:analyze).and_return(result_with("fallback", "fallback"))

      status = nil
      expect { status = described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options) }.to output.to_stderr

      expect(status).to eq(1)
      expect(SFL::Formatters::ReportWriter).to have_received(:write).with(anything, "./out")
    end

    it "names the degraded file in the aggregated failure summary of a multi-file run" do
      allow(described_class).to receive(:gather_conversation_files).and_return(
        [
          { path: "spec/fixtures/inputs/sample.jsonl", source_type: "chat_native", label: "a" },
          { path: "spec/fixtures/inputs/sillytavern_group.jsonl", source_type: "chat_native", label: "b" },
]
      )
      allow(engine).to receive(:analyze).and_return(result_with("fallback"), result_with("llm"))

      expect { expect(described_class.run_conversation("./dir", options)).to eq(1) }
        .to output(%r{1/2 conversations failed: a \(1 fallback clauses\)}).to_stderr
    end

    it "keeps going after a file that raises and names it in the failure summary" do
      allow(described_class).to receive(:gather_conversation_files).and_return(
        [
          { path: "spec/fixtures/inputs/sample.jsonl", source_type: "chat_native", label: "a" },
          { path: "spec/fixtures/inputs/sillytavern_group.jsonl", source_type: "chat_native", label: "b" },
        ]
      )
      calls = 0
      allow(engine).to receive(:analyze) do
        calls += 1
        raise SFL::Analysis::Error, "bad export" if calls == 1

        result_with("llm")
      end

      expect { expect(described_class.run_conversation("./dir", options)).to eq(1) }
        .to output(%r{\[ERROR\] a: bad export.*1/2 conversations failed: a}m).to_stderr
      expect(engine).to have_received(:analyze).twice
    end

    it "does not fail a --pass1-only run, whose stub values are what the operator asked for" do
      allow(engine).to receive(:analyze).and_return(result_with("stub", "stub"))

      expect { expect(described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options.merge(pass1_only: true))).to eq(0) }
        .to output.to_stderr
    end

    it "honors --allow-fallback as the explicit opt-out, but only when asked" do
      allow(engine).to receive(:analyze).and_return(result_with("fallback"))

      expect { expect(described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options.merge(allow_fallback: true))).to eq(0) }
        .to output.to_stderr
    end
  end

  # Narrative generation is best-effort: the analysis trio is already on disk,
  # so a narrator provider failure downgrades to a warning. The guarantee rests
  # on NarrativeGenerator#generate converting ANY StandardError into
  # NarrativeError; narrowing that rescue would turn a provider outage into a
  # failed batch with no other test noticing.
  describe ".run_conversation with --narrative" do
    let(:digest) { instance_double(SFL::Analysis::NarrativeGenerator::Digest, to_text: "digest", source: "a") }

    before do
      allow(engine).to receive(:analyze).and_return(result_with("llm", "llm"))
      allow(SFL::Analysis::NarrativeGenerator::Digest).to receive(:from_result).and_return(digest)
      allow(boot_result.lm_factory).to receive(:for).with(:narrative_generation).and_return(:lm)
    end

    it "warns instead of failing the run when the narrator raises a provider error" do
      narrator = -> (_digest_text) { raise IOError, "provider unreachable" }
      allow(SFL::LLM::Narrators::NarrativeGenerator).to receive(:new).and_return(narrator)
      allow(SFL::Formatters::NarrativeFormatter).to receive(:new)

      status = nil
      expect { status = described_class.run_conversation("spec/fixtures/inputs/sample.jsonl", options.merge(narrative: true)) }
        .to output(/\[WARN\] narrative generation failed: Narrative generation failed: provider unreachable/).to_stderr

      expect(status).to eq(0)
      expect(SFL::Formatters::ReportWriter).to have_received(:write).with(anything, "./out")
      expect(SFL::Formatters::NarrativeFormatter).not_to have_received(:new)
    end
  end

  describe ".run" do
    it "propagates run_conversation's non-zero status as the process exit code" do
      allow(described_class).to receive(:run_conversation).and_return(1)

      expect(described_class.run(%w[conversation spec/fixtures/inputs/sample.jsonl])).to eq(1)
    end
  end
end
