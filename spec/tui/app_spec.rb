# frozen_string_literal: true

require "tmpdir"
require_relative "spec_helper"

RSpec.describe SFL::TUI::App do
  let(:logger) { SFL::Core::Ports::Null::Logger.new }
  let(:settings) do
    SFL::Boot::TerminalSettings.new(reviewer: "ana", editor: "nano", export_dir: "/tmp/exports",
      ingest_log_dir: "/tmp/logs", kitty_window_id: nil, kitty_listen_on: nil)
  end
  let(:boot) { SFL::Boot::Result.new(db: instance_double(Sequel::Database), spacy_model: "en_core_web_sm") }

  describe ".build" do
    it "wires the Postgres collaborators and the settings into the services" do
      services = described_class.build(boot:, logger:, settings:).services

      expect(services.source).to be_a(SFL::Store::PgBrowseSource)
      expect(services.review_queue).to be_a(SFL::Store::PgReviewQueueRepository)
      expect(services.run_log).to be_a(SFL::Store::PgRunRepository)
      expect(services.retriever).to be_a(SFL::Store::PgHybridRetriever)
      expect(services.editor).to be_a(SFL::Core::Ports::ShellEditor)
      expect(services.opener).to be_a(SFL::Core::Ports::XdgOpener)
      expect(services.exporter).to be_a(SFL::Export::Exporter)
      expect(services.reviewer).to eq("ana")
    end

    it "wires the null terminal host outside kitty, the detached-child spawner and no run header without LLM settings" do
      services = described_class.build(boot:, logger:, settings:).services

      expect(services.terminal_host).to be_a(SFL::Core::Ports::Null::TerminalHost)
      expect(services.spawner).to be_a(SFL::TUI::Launcher::DetachedChild)
      expect(services.run_models).to be_nil
    end

    # Facts 65 and 67: the run header comes from Boot; kitty only with a window id and a reachable socket.
    it "passes the llm_config header and chooses kitty from the settings" do
      config = instance_double(SFL::LLM::Config, header: { "pass_two_annotation" => {} })
      allow(SFL::Core::Ports::KittyHost).to receive(:detect).and_call_original
      services = described_class.launch_services(boot.dup.tap { |result| result.llm_config = config },
        settings.with(kitty_window_id: "20", kitty_listen_on: "unix:/tmp/no-such-kitty-socket"), logger)

      expect(services[:run_models]).to eq({ "pass_two_annotation" => {} })
      expect(services[:terminal_host]).to be_a(SFL::Core::Ports::Null::TerminalHost)
      expect(SFL::Core::Ports::KittyHost).to have_received(:detect)
        .with(window_id: "20", listen_on: "unix:/tmp/no-such-kitty-socket")
    end

    it "boots without the LLM settings when they are missing" do
      allow(SFL::Boot).to receive(:call).with(require_db: true, require_llm: true, require_tracing: false)
        .and_raise(SFL::Boot::Error, "OPENROUTER_API_KEY missing")
      allow(SFL::Boot).to receive(:call).with(require_db: true, require_llm: false, require_tracing: false).and_return(boot)

      expect(described_class.build(logger:, settings:).boot).to be(boot)
    end
  end

  describe ".recompiler" do
    it "fails without the LLM settings" do
      expect(described_class.recompiler(boot, logger).call("t", section_id: "s")).to eq(Dry::Monads::Failure(described_class::NO_LLM))
    end

    it "builds the pipeline once and compiles with store and embed on" do
      pipeline = instance_double(SFL::Core::Pipeline, compile: Dry::Monads::Success(:ok))
      allow(SFL::CLI).to receive(:build_pipeline).and_return(pipeline)
      recompile = described_class.recompiler(boot.dup.tap { |result| result.llm_config = :config }, logger)

      2.times { recompile.call("text", section_id: "s") }

      expect(SFL::CLI).to have_received(:build_pipeline).once
      expect(pipeline).to have_received(:compile).with("text", section_id: "s", store: true, embed: true).twice
    end
  end

  describe ".key_message" do
    it "turns a key event into a key message and ignores other events" do
      key = RatatuiRuby::Event::Key.new(code: "q")

      expect(described_class.key_message(key)).to eq(SFL::TUI::Messages::Key.new("q"))
      expect(described_class.key_message(RatatuiRuby::Event::Resize.new(width: 1, height: 1))).to be_nil
    end
  end

  describe ".run" do
    it "runs the event loop inside the terminal session until quit" do
      tui = Class.new do
        def draw = nil

        def poll_event(timeout:)
          RatatuiRuby::Event::Key.new(code: "q") if timeout
        end
      end.new
      terminal = Class.new { define_method(:run) { |&block| block.call(tui) } }.new
      context = SFL::TUI::AppContext.new(boot:, logger:, services: SFL::TUI::Services.null)

      expect { described_class.run(context, terminal:) }.not_to raise_error
    end
  end

  describe ".run polling" do
    it "sends a Tick when a poll brings no key, so the Runs tab re-reads the run log (fact 53)" do
      events = [nil, RatatuiRuby::Event::Key.new(code: "q")]
      tui = Class.new do
        define_method(:draw) { nil }
        define_method(:poll_event) { |timeout:| timeout && events.shift }
      end.new
      terminal = Class.new { define_method(:run) { |&block| block.call(tui) } }.new
      run_log = SFL::Core::Ports::Null::RunLog.new
      allow(run_log).to receive(:list).and_call_original
      context = SFL::TUI::AppContext.new(boot:, logger:, services: SFL::TUI::Services.null(run_log:))

      described_class.run(context, terminal:)

      expect(run_log).to have_received(:list).twice
    end
  end

  describe "Browse over the Postgres adapters" do
    let(:db) { SFL::Store::StoreTestDb.db }

    before do
      SFL::Store::StoreTestDb.clean!
      collection_id = SFL::Store::PgCollectionRepository.new(db).find_or_create("papers")[:id]
      document_id = SFL::Store::PgDocumentRepository.new(db).upsert(collection_id:, document_key: "paper.md", title: "Paper")[:id]
      SFL::Store::PgSectionRepository.new(db).upsert(document_id, "paper.md#intro", ordinal: 1, kind: "heading", label: "Intro",
        clause_count: 1)
      db[:clauses].insert(external_id: "c-1", text: "Intro clause.", section_id: "paper.md#intro", sentence_index: 0, root_index: 0)
      db[:ideational_payloads].insert(clause_id: "c-1", process_type: "material")
      db[:interpersonal_payloads].insert(clause_id: "c-1", mood: "declarative", modality_weight: 0.5, tenor: 0.5,
        annotation_source: "llm")
    end

    # Facts 41, 44, 45 end to end: select a section, export JSONL, see the
    # path in the status line and an export run in the runs table.
    it "selects a section, exports it and records the export run" do
      Dir.mktmpdir do |dir|
        services = described_class.services(SFL::Boot::Result.new(db:), settings.with(export_dir: dir), logger)
        keys = ["down", "enter", "down", " ", "e", "j", "q"].map { |key| TUISpecSupport.key(key) }
        final = SFL::TUI::EventLoop.new(services:, draw: -> (_state) {}, next_message: -> { keys.shift }).run
        path = Dir[File.join(dir, "papers-*.jsonl")].first

        expect(SFL::TUI::Program.status_line(final)).to eq("selected: 1 sections, 1 clauses | exported 1 clauses to #{path}")
        expect(JSON.parse(File.read(path))).to include("section_id" => "paper.md#intro", "text" => "Intro clause.")
        expect(db[:runs].all).to contain_exactly(hash_including(kind: "export", collection: "papers", status: "finished", done: 1))
      end
    end
  end
end
