# frozen_string_literal: true

require "spec_helper"
require "dspy"
require "ratatui_ruby"

# Which display a foreground run gets: the full-screen dashboard on a
# terminal, the plain `progress turn=N total=M` lines otherwise.
RSpec.describe SFL::CLI do
  let(:llm_config) do
    SFL::LLM::Config.new(tasks: { pass_two_annotation: SFL::LLM::TaskConfig.new(provider: :openrouter, model: "m1") })
  end
  let(:boot_result) do
    SFL::Boot::Result.new(
      db: instance_double(Sequel::Database), llm_config:, lm_factory: instance_double(SFL::LLM::LMFactory),
      embedder: instance_double(SFL::LLM::Embedder), pass1_command: nil, spacy_model: "en_core_web_sm"
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
      collection: "chats",
    }
  end
  let(:result) do
    turn = instance_double(SFL::Core::Types::ConversationTurn, clauses: [])
    instance_double(SFL::Core::Types::AnalysisResult, metadata: { interrupted: false }, turns: [turn])
  end
  let(:screens) { [] }
  # Draws into ratatui's test terminal; the poll never brings a key.
  let(:terminal) do
    drawn = screens
    tui_class = Class.new(SimpleDelegator) { define_method(:poll_event) { |timeout:| sleep(timeout / 100.0) && nil } }
    Class.new do
      define_method(:run) do |&block|
        RatatuiRuby.init_test_terminal(100, 30)
        block.call(tui_class.new(RatatuiRuby::TUI.new))
      ensure
        drawn << RatatuiRuby.get_buffer_content
        RatatuiRuby.restore_terminal
      end
    end.new
  end

  before do
    allow(SFL::Core::PassOne::SpacySidecarParser).to receive(:new)
      .and_return(instance_double(SFL::Core::PassOne::SpacySidecarParser))
    allow(SFL::Boot).to receive_messages(call: boot_result, run_id: "run-7")
    allow(SFL::LLM::EngineBuilder).to receive(:call).and_return(instance_double(SFL::LLM::Engine))
    allow(SFL::Analysis::Engine).to receive(:new).and_return(engine)
    allow(SFL::Analysis::ConversationSource).to receive(:new)
      .and_return(instance_double(SFL::Analysis::ConversationSource))
    allow(SFL::Formatters::ReportWriter).to receive(:write).and_return({ json: "./out/a.json" })
    allow(described_class).to receive(:gather_conversation_files)
      .and_return([{ path: "spec/fixtures/inputs/sample.jsonl", source_type: "chat_native", label: "a" }])
    allow(engine).to receive(:analyze).and_return(result)
    allow(SFL::Dashboard::Session).to(receive(:new).and_wrap_original { |original, **args| original.call(**args, terminal:, hold: false) })
  end

  describe "when stdout or stderr is not a terminal (fact 52)" do
    it "draws no dashboard and leaves the engine's plain progress line on" do
      expect(described_class.run_conversation("a.jsonl", options)).to eq(0)

      expect(SFL::Dashboard::Session).not_to have_received(:new)
      expect(SFL::Analysis::Engine).to have_received(:new).with(hash_excluding(:progress_writer))
      expect(screens).to be_empty
    end

    it "returns the options unchanged and logs to stderr" do
      expect(described_class.with_dashboard(boot_result, options, SFL::CLI::StopFlag.new, kind: "ingest", documents: 1))
        .to eq(options)
      expect(described_class.build_collaborators(options).first).to be_a(SFL::Core::Ports::StderrLogger)
    end
  end

  describe "when stdout and stderr are terminals (fact 46)" do
    before { allow(described_class).to receive(:terminal?).and_return(true) }

    it "runs the annotation under the full-screen dashboard and silences the plain progress line" do
      expect(described_class.run_conversation("a.jsonl", options)).to eq(0)

      expect(SFL::Analysis::Engine).to have_received(:new).with(hash_including(progress_writer: kind_of(Proc)))
      expect(screens.last).to include("sfl annotate · finished", "run run-7", "collection chats",
        "pass_two_annotation openrouter/m1")
    end

    it "routes the log and the run sink through the dashboard" do
      dashboard_options = described_class.with_dashboard(boot_result, options, SFL::CLI::StopFlag.new, kind: "annotate",
        documents: 2)
      dashboard = dashboard_options[:dashboard]
      logger, = described_class.build_collaborators(dashboard_options)
      logger.info("to the screen")
      described_class.build_run_sink(boot_result, dashboard_options, kind: "annotate").start(3)

      expect(dashboard.board.state).to have_attributes(kind: "annotate", documents_total: 2, sections_total: 3)
      expect(dashboard.board.state.log.last).to include("to the screen")
    end
  end

  describe ".terminal?" do
    before { allow(described_class).to receive(:terminal?).and_call_original }

    it "is true only when both stdout and stderr are terminals" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow($stderr).to receive(:tty?).and_return(false)
      expect(described_class.terminal?).to be(false)

      allow($stderr).to receive(:tty?).and_return(true)
      expect(described_class.terminal?).to be(true)
    end
  end

  describe ".task_models" do
    it "names provider and model per task, and nothing without LLM settings" do
      expect(described_class.task_models(llm_config)).to eq(["pass_two_annotation openrouter/m1"])
      expect(described_class.task_models(nil)).to eq([])
    end
  end

  describe ".ingest_document_count" do
    it "counts the files the ingest walk visits" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), "# A")
        File.write(File.join(dir, "b.md"), "# B")

        expect(described_class.ingest_document_count(dir)).to eq(2)
      end
    end
  end
end
