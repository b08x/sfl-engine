# frozen_string_literal: true

require "optparse"
require "json"
require "fileutils"
require "timeout"
require "ruby_llm"

module SFL
  # sfl-analyze command line interface. Owns argv parsing, terminal
  # output, and exit codes — and nothing else. All logic lives in
  # Boot/Core::Pipeline/Analysis::Engine/Analysis::KnowledgeBaseSource/
  # Retrieval::ContextSynthesizer; `.parse` is a pure function so it is
  # testable without touching a database or LLM.
  #
  # Scope for this slice: four subcommands (conversation, documentation,
  # knowledge-base, context). Deliberately NOT ported, each for a
  # documented reason:
  #   - `narrate <analysis.json>` — needs Analysis::NarrativeGenerator::
  #     Digest.from_json, which Phase 3 explicitly left unbuilt (see that
  #     class's own comment). The `--narrative` flag WITHIN conversation/
  #     documentation (Digest.from_result, which DOES exist) is in scope
  #     and implemented below.
  #   - `tui` subcommand / any `--live` flag — superseded by track
  #     decision 10 (GUI replaces TUI) and belongs to Phase 5's `jobs/`
  #     work (Sidekiq/Gush), not this phase.
  #   - `--sprint-id` — GEB-sprint machinery, stays quarantined to
  #     experiments/ (Phase 5); Formatters::MarkdownFormatter already
  #     dropped support for it.
  #   - interactive Chat::Session wiring (legacy's `run_tui`) — Phase 5
  #     (track decision 11), lib/sfl/chat/ doesn't exist yet.
  # rubocop:disable Metrics/ModuleLength -- an entry point's job is argv parsing (four
  # parse_*_options methods) plus four run_* use-case drivers plus the one wiring factory that
  # replaces what used to be 4x duplicated (build_pipeline) plus shared small helpers
  # (progress printers, the interrupt trap, report/narrative writers) — StopFlag already got its
  # own file precisely because it IS a separable concern; this is what's left after that split.
  module CLI
    class UsageError < SFL::Error; end

    USAGE = <<~TEXT
      Usage: sfl-analyze <subcommand> <input> [options]

      Subcommands:
        conversation <input>         Analyze a JSONL conversation, or a subtitle
                                      file (.srt/.vtt/.ass) treated as a
                                      single-conversation transcript — or a folder
                                      of any of these (one report per file, in
                                      subdirectories of --output-dir named after
                                      each file)
        documentation <path>         Analyze a markdown/PDF file or directory
        knowledge-base <path>        Assess a KB directory for migration —
                                      classifies artifacts, scores quality,
                                      and produces a migration manifest
        context "<query>"            Query stored clauses, synthesize an answer

      Common options:
        --output-dir DIR             Where to write reports [./output/latest]
        --disable-tracing            Skip OpenTelemetry/Langfuse tracing setup

      conversation/documentation:
        --pass1-only                 Skip LLM annotation (placeholder values)
        --narrative                  Also generate narrative_report.md (LLM)
        --topics N                   Number of topics for LDA; 0 = HDP (auto-discover)
        --resume                     Reuse cached Pass 2 results from previous runs
        --store                      Persist clauses + embeddings for `context`

      knowledge-base:
        --store                      Persist clauses + embeddings for `context`
        --images / --no-images       Analyze image files via vision LLM (default off)
        --vision-model MODEL         Vision LLM model id (currently informational
                                      only — see LLM::ChatFactory#for's known limitation
                                      noted in #build_kb_source below)
        --resume                     Reuse cached Pass 2 results from previous runs
        --annotated                  Also write annotated/*.md

      context:
        --mood MOOD                  declarative|interrogative|imperative|exclamative
        --min-tenor F  --max-tenor F
        --min-modality F  --max-modality F
        --limit N                    Max clauses to retrieve [10]
    TEXT

    DEFAULT_OUTPUT_DIR = "./output/latest"

    # @param argv [Array<String>]
    # @return [Hash] {command:, input:, options:}
    module_function def parse(argv)
      argv = argv.dup
      command = argv.shift&.tr("-", "_")&.to_sym
      unless %i[conversation documentation knowledge_base context].include?(command)
        raise UsageError, "Unknown subcommand: #{command}\n\n#{USAGE}"
      end

      input = argv.shift
      raise UsageError, "#{command} requires an input argument\n\n#{USAGE}" if input.nil? || input.start_with?("--")

      options = __send__(:"parse_#{command}_options", argv)
      { command:, input:, options: }
    end

    # Shared across every parse_*_options method so `--disable-tracing`
    # behaves identically everywhere instead of being redefined 4×.
    module_function def add_tracing_option(opt, options)
      options[:disable_tracing] = false
      opt.on("--disable-tracing") { options[:disable_tracing] = true }
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat defaults-Hash-plus-
    # OptionParser-block per flag, ported verbatim from legacy's own parse_conversation_options;
    # each `opt.on` line is already the smallest unit this can be split into.
    module_function def parse_conversation_options(argv)
      options = {
        output_dir: DEFAULT_OUTPUT_DIR,
        pass1_only: false,
        resume: false,
        store: false,
        narrative: false,
        topics: nil,
      }
      OptionParser.new do |opt|
        opt.on("--output-dir DIR") { |v| options[:output_dir] = v }
        opt.on("--pass1-only") { options[:pass1_only] = true }
        opt.on("--resume") { options[:resume] = true }
        opt.on("--store") { options[:store] = true }
        opt.on("--narrative") { options[:narrative] = true }
        opt.on("--topics N", Integer) { |v| options[:topics] = v }
        add_tracing_option(opt, options)
      end.parse!(argv)
      options
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    module_function def parse_documentation_options(argv)
      parse_conversation_options(argv) # identical option surface for this slice
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- see parse_conversation_options above
    module_function def parse_knowledge_base_options(argv)
      options = {
        output_dir: DEFAULT_OUTPUT_DIR,
        store: false,
        images: false,
        vision_model: nil,
        resume: false,
        annotated: false,
      }
      OptionParser.new do |opt|
        opt.on("--output-dir DIR") { |v| options[:output_dir] = v }
        opt.on("--store") { options[:store] = true }
        opt.on("--images") { options[:images] = true }
        opt.on("--no-images") { options[:images] = false }
        opt.on("--vision-model MODEL") { |v| options[:vision_model] = v }
        opt.on("--resume") { options[:resume] = true }
        opt.on("--annotated") { options[:annotated] = true }
        add_tracing_option(opt, options)
      end.parse!(argv)
      options
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- see parse_conversation_options above
    module_function def parse_context_options(argv)
      options = { output_dir: nil, limit: 10, filters: {} }
      OptionParser.new do |opt|
        opt.on("--output-dir DIR") { |v| options[:output_dir] = v }
        opt.on("--limit N", Integer) { |v| options[:limit] = v }
        opt.on("--mood MOOD") { |v| options[:filters][:mood] = v }
        opt.on("--min-tenor F", Float) { |v| options[:filters][:min_tenor] = v }
        opt.on("--max-tenor F", Float) { |v| options[:filters][:max_tenor] = v }
        opt.on("--min-modality F", Float) { |v| options[:filters][:min_modality] = v }
        opt.on("--max-modality F", Float) { |v| options[:filters][:max_modality] = v }
        add_tracing_option(opt, options)
      end.parse!(argv)
      options
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Entry point for exe/sfl-analyze. Returns the process exit code.
    # No un-rescued crash for expected operational failures (D9): bad
    # args, Boot-time misconfiguration (missing API key, DB connection
    # failure, cancelled tracing), a Pipeline#compile failure surfaced
    # through Analysis::Error, or a provider-side LLM/HTTP failure that
    # escaped Pass 2's own degradation ladder (only Retrieval::
    # ContextSynthesizer's synthesis call is NOT internally degraded —
    # see that class's own comment: "a failed synthesis call propagates
    # — there is no useful default answer").
    # rubocop:disable Metrics/MethodLength -- one dispatch line plus three rescue clauses, each
    # mapping a distinct failure category to a message/exit-code pair; ported verbatim from
    # legacy's own CLI.run.
    module_function def run(argv)
      parsed = parse(argv)
      __send__(:"run_#{parsed[:command]}", parsed[:input], parsed[:options])
      0
    rescue UsageError => e
      warn e.message
      1
    rescue Boot::Error, Analysis::Error, Timeout::Error => e
      warn "[ERROR] #{e.message}"
      1
    rescue RubyLLM::Error => e
      # Provider-side failures (rate limits, empty responses, auth) are
      # routine operational errors, not bugs — no backtrace.
      warn "[ERROR] LLM provider error: #{e.message}"
      1
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # -- one flat file-dispatch/compile/report loop, ported verbatim from legacy's own
    # run_conversation; every step is already its own private method call (build_conversation_engine,
    # finish_report, write_narrative, print_interrupt_status) — the loop wiring itself is what's left.
    module_function def run_conversation(input, options)
      stop_flag = StopFlag.new
      install_interrupt_trap(stop_flag)

      files = File.directory?(input) ? Dir.glob(File.join(input, "**", "*.{jsonl,srt,vtt,ass}")) : [input]
      raise UsageError, "No .jsonl/.srt/.vtt/.ass files found in #{input}" if files.empty?

      boot_result = Boot.call(require_llm: !options[:pass1_only], require_tracing: !options[:disable_tracing])
      engine = build_conversation_engine(boot_result, options, stop_flag)

      files.each do |file|
        break if stop_flag.stopped?

        puts "=== #{File.basename(file)} ===" if files.size > 1
        source = Analysis::ConversationSource.new(file)
        result = engine.analyze(source, label: File.basename(file, ".*"), store: options[:store],
          resume: options[:resume], topics: options[:topics], pass_one_only: options[:pass1_only])
        output_dir = if files.size > 1
          File.join(options[:output_dir],
            File.basename(file, ".*"))
        else
          options[:output_dir]
        end
        finish_report(result, output_dir)
        write_narrative(result, output_dir, boot_result) if options[:narrative]
        print_interrupt_status(result, file, :conversation) if result.metadata[:interrupted]
      end
    ensure
      Signal.trap("INT", "DEFAULT")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat boot/compile/report
    # sequence, ported verbatim from legacy's own run_documentation; every step is already its
    # own private method call.
    module_function def run_documentation(input, options)
      stop_flag = StopFlag.new
      install_interrupt_trap(stop_flag)

      boot_result = Boot.call(require_llm: !options[:pass1_only], require_tracing: !options[:disable_tracing])
      engine = build_conversation_engine(boot_result, options, stop_flag)

      source = Analysis::DocumentationSource.new(input)
      result = engine.analyze(source, label: File.basename(input.to_s, ".*"), store: options[:store],
        resume: options[:resume], topics: options[:topics], pass_one_only: options[:pass1_only])
      finish_report(result, options[:output_dir])
      write_narrative(result, options[:output_dir], boot_result) if options[:narrative]
      print_interrupt_status(result, input, :documentation) if result.metadata[:interrupted]
    ensure
      Signal.trap("INT", "DEFAULT")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat boot/compile/write-trio
    # sequence, ported verbatim from legacy's own run_knowledge_base; every step is already its
    # own private method call (build_kb_source) or a single formatter/writer call.
    module_function def run_knowledge_base(input, options)
      stop_flag = StopFlag.new
      install_interrupt_trap(stop_flag)

      # Always require_llm: true (unlike conversation/documentation) —
      # this subcommand has no --pass1-only option (see
      # parse_knowledge_base_options), matching legacy's own
      # KnowledgeBaseAnalyzer, which never skipped Pass 2 either.
      boot_result = Boot.call(require_llm: true, require_tracing: !options[:disable_tracing])
      source = build_kb_source(boot_result, options, stop_flag)

      result = source.analyze(input, store: options[:store], resume: options[:resume])

      paths = Formatters::KBReportWriter.write(result, options[:output_dir])
      puts "\nGenerated:"
      paths.each { |format, path| puts "  #{format.to_s.upcase}: #{path}" }

      if options[:annotated]
        annotated_paths = Formatters::KBAnnotatedDocWriter.write(result, options[:output_dir])
        puts "  ANNOTATED: #{annotated_paths.size} file(s) in #{File.join(options[:output_dir], 'annotated')}/"
      end

      puts "\nArtifacts: #{result.metadata[:artifact_count]} " \
        "| Stale: #{result.staleness_flags.size} " \
        "| Files: #{result.metadata[:file_count]}"
    ensure
      Signal.trap("INT", "DEFAULT")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat boot/synthesize/print/
    # write-file sequence, ported verbatim from legacy's own run_context.
    module_function def run_context(query, options)
      boot_result = Boot.call(require_llm: true, require_tracing: !options[:disable_tracing])
      logger, instrumenter, breaker = build_collaborators

      synthesizer = Retrieval::ContextSynthesizer.new(
        retriever: Store::PgHybridRetriever.new(db: boot_result.db, embedder: boot_result.embedder),
        chat: boot_result.chat_factory.for(:context_synthesis),
        breaker:, instrumenter:, logger:
      )

      result = synthesizer.synthesize(query, filters: options[:filters], limit: options[:limit])

      if result.retrieved_count.zero?
        puts "No stored clauses matched. Ingest documents first:"
        puts "  sfl-analyze documentation <path> --store"
        return
      end

      if result.answer.nil?
        puts "Synthesis failed — showing retrieved evidence only:"
      else
        puts "## Answer (confidence: #{result.confidence})\n\n#{result.answer}\n\n"
        puts "## Evidence (#{result.retrieved_count} retrieved, #{result.cited_clause_ids.size} cited)"
      end
      print_evidence(result)

      return unless options[:output_dir]

      FileUtils.mkdir_p(options[:output_dir])
      path = File.join(options[:output_dir], "context_synthesis.json")
      File.write(path, JSON.pretty_generate(result.to_h))
      puts "\nWritten: #{path}"
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # The T4 fix: every run_* method above composes its Pipeline/Engine
    # through exactly this one factory instead of four independently
    # near-identical copies. Shared collaborator construction
    # (logger/instrumenter/breaker) lives in #build_collaborators below,
    # also shared by run_context (which needs the same three ports for
    # ContextSynthesizer but has no Pipeline of its own).
    #
    # --pass1-only wiring: Core::Pipeline#initialize requires both
    # pass_one:/pass_two: (see that class's constructor) even though
    # Pipeline#compile's own `pass_one_only:` kwarg (passed per-call by
    # Analysis::Engine#analyze, forwarded from options[:pass1_only] above)
    # already stubs every clause via Ports::Null::Annotator internally
    # when true — #annotate never actually calls `pass_two` in that path
    # (see Pipeline#annotate: `return Success(stub_annotate_all(pairs)) if
    # pass_one_only`). So a real LLM::Engine built via EngineBuilder is
    # never invoked when --pass1-only is set; injecting
    # Ports::Null::Annotator.new here only satisfies the required kwarg
    # cheaply, while Boot.call(require_llm: false) is what actually saves
    # the API-key-validation/ChatFactory cost.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat Pipeline composition, each
    # of Pipeline's nine kwargs assembled by exactly one line; the card's own fix for what was 4x
    # duplicated elsewhere, not something to fragment further within this one method.
    module_function def build_pipeline(boot_result, options, breaker:, instrumenter:, logger:)
      parser = Core::PassOne::SpacySidecarParser.new(model: boot_result.spacy_model,
        command: boot_result.pass1_command, logger:)
      pass_one = Core::PassOne::Engine.new(parser:, instrumenter:, logger:)

      pass_two = if options[:pass1_only]
        Core::Ports::Null::Annotator.new
      else
        LLM::EngineBuilder.call(config: boot_result.llm_config, chat_factory: boot_result.chat_factory,
          breaker:, instrumenter:, logger:)
      end

      clause_store = Store::PgClauseStore.new(boot_result.db)
      embedding_store = options[:store] ? Store::PgEmbeddingStore.new(boot_result.db) : Core::Ports::Null::EmbeddingStore.new
      embedder = options[:store] ? boot_result.embedder : Core::Ports::Null::Embedder.new
      cache = options[:resume] ? Core::Ports::FileCache.new : Core::Ports::Null::Cache.new

      Core::Pipeline.new(pass_one:, pass_two:, clause_store:, embedding_store:, embedder:, cache:, logger:,
        instrumenter:)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    module_function def build_conversation_engine(boot_result, options, stop_flag)
      logger, instrumenter, breaker = build_collaborators
      pipeline = build_pipeline(boot_result, options, breaker:, instrumenter:, logger:)
      review_queue_repo = options[:store] ? Store::PgReviewQueueRepository.new(boot_result.db) : nil

      Analysis::Engine.new(
        pipeline:, review_queue_repo:,
        on_progress: progress_printer, on_turn_start: progress_starter,
        stop_requested: -> { stop_flag.stopped? }
      )
    end

    # Known limitation: --vision-model has no effect. LLM::ChatFactory#for
    # only resolves {provider, model} from the injected LLM::Config — it
    # has no per-call model-override parameter (verified against its
    # actual #for(task) implementation), so there is currently no way to
    # honor a per-invocation --vision-model without inventing new
    # ChatFactory API, which this slice deliberately does not do. Set
    # SFL_TASK_CONTEXT_SYNTHESIS_MODEL (the ENV convention Boot already
    # supports) to a vision-capable model instead.
    #
    # :context_synthesis is reused as the vision task (same judgment call
    # as write_narrative's narrator chat below) — Boot::TASK_NAMES has no
    # dedicated vision task, and reusing the one general-purpose chat task
    # already registered is more defensible than inventing an unrelated
    # default.
    module_function def build_kb_source(boot_result, options, stop_flag)
      logger, instrumenter, breaker = build_collaborators
      pipeline = build_pipeline(boot_result, options, breaker:, instrumenter:, logger:)
      review_queue_repo = options[:store] ? Store::PgReviewQueueRepository.new(boot_result.db) : nil
      chat = boot_result.chat_factory.for(:context_synthesis) if options[:images]

      Analysis::KnowledgeBaseSource.new(
        pipeline:, review_queue_repo:,
        on_progress: kb_progress_printer, stop_requested: -> { stop_flag.stopped? },
        analyze_images: options[:images], chat:
      )
    end

    module_function def build_collaborators
      logger = Core::Ports::StandardLogger.new(progname: "sfl.cli")
      instrumenter = Core::Ports::Null::Instrumenter.new
      breaker = Core::Ports::Null::Breaker.new
      [logger, instrumenter, breaker]
    end

    module_function def print_evidence(result)
      result.clauses.each_with_index do |clause, idx|
        marker = result.cited_clause_ids.include?(clause[:clause_id]) ? "*" : " "
        puts "#{marker} [#{idx + 1}] #{clause[:text]} (#{clause[:document_id]})"
      end
    end

    # Fires immediately, before a turn/section's compilation starts —
    # a single turn's Pass 1 + Pass 2 can take 20-60s, so without this
    # the terminal sits static with no signal the run hasn't hung.
    # No trailing newline: progress_printer completes the same line.
    module_function def progress_starter
      lambda do |event|
        print "  #{event[:turn_id]}/#{event[:total]} (#{event[:speaker]})... "
        $stdout.flush
      end
    end

    module_function def progress_printer
      lambda do |event|
        label = event[:defaulted].zero? ? "OK" : "#{event[:defaulted]}/#{event[:clause_count]} DEFAULTED"
        puts "#{event[:elapsed]}s [#{label}]"
      end
    end

    module_function def kb_progress_printer
      lambda do |event|
        puts "  #{event[:artifact_id]}/#{event[:total]} [#{File.basename(event[:source_file])}] #{event[:title]}"
      end
    end

    # "Clean quit": the first Ctrl+C sets the flag so Analysis::Engine/
    # Analysis::KnowledgeBaseSource finish the in-flight turn/artifact,
    # then stop on their own rather than this handler tearing anything
    # down directly. A second Ctrl+C (flag already set) restores the
    # default disposition and re-sends SIGINT to this process, so a user
    # who wants to hard-kill still can.
    #
    # legacy's with_interrupts_deferred (guarding PyCall's spaCy import
    # against a same-instant Ctrl+C landing inside CPython's own signal
    # machinery) is NOT ported: Pass 1 is now a subprocess sidecar spoken
    # to over Open3.popen2 (track decision 2) — there is no in-process
    # CPython call for a Ruby-level SIGINT to interrupt mid-C-call, only
    # ordinary pipe I/O, so that hazard doesn't exist here.
    module_function def install_interrupt_trap(stop_flag)
      Signal.trap("INT") do
        if stop_flag.stopped?
          Signal.trap("INT", "DEFAULT")
          Process.kill("INT", Process.pid)
        else
          stop_flag.stop!
          warn "\n[INFO] Stopping after the current turn finishes... (Ctrl+C again to force quit)"
        end
      end
    end

    module_function def print_interrupt_status(result, input, command)
      meta = result.metadata
      puts "\nStopped after #{result.turns.size}/#{meta[:total]} in #{File.basename(input.to_s)}."
      puts "   Resume with: sfl-analyze #{command} #{input} --resume " \
        "(cached turns are skipped; only the rest gets re-analyzed)"
    end

    # Best-effort: the analysis trio is already on disk; a narrative
    # failure downgrades to a warning rather than failing the run.
    #
    # Narrator chat task: :context_synthesis is reused rather than
    # inventing an unregistered task name — Boot::TASK_NAMES has no
    # dedicated :narrative_generation entry, and :context_synthesis is
    # the only other "general free-form LLM call" task already wired
    # (unlike :pass_two_annotation/:pass_two_batch_annotation, which are
    # schema-shaped specifically for clause annotation).
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat digest/generate/check/
    # write sequence, ported verbatim from legacy's own write_narrative.
    module_function def write_narrative(result, output_dir, boot_result)
      unless boot_result.chat_factory
        warn "[WARN] narrative generation skipped: --narrative requires an LLM (omit --pass1-only)"
        return
      end

      digest = Analysis::NarrativeGenerator::Digest.from_result(result)
      narrator = LLM::Narrators::NarrativeGenerator.new(chat: boot_result.chat_factory.for(:context_synthesis))
      report = Analysis::NarrativeGenerator.new(narrator:).generate(digest)
      source_clauses = result.turns.flat_map(&:clauses)
      narrative_text = report_sections_text(report)
      citation_check = Analysis::CitationGroundingChecker.new.check(narrative_text, source_clauses)
      path = File.join(output_dir, "narrative_report.md")
      Formatters::NarrativeFormatter.new(report, citation_check:).write_to(path)
      puts "  NARRATIVE: #{path}"
    rescue Analysis::NarrativeError => e
      warn "[WARN] narrative generation failed: #{e.message}"
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    module_function def report_sections_text(report)
      %i[overview cast_and_roles interpersonal_dynamics conversational_arc data_quality takeaways]
        .map { |k| report.public_send(k) }.join("\n\n")
    end

    # rubocop:disable Metrics/AbcSize -- one flat write/warn/print sequence, ported verbatim from
    # legacy's own finish_report.
    module_function def finish_report(result, output_dir)
      paths = Formatters::ReportWriter.write(result, output_dir)

      clauses = result.turns.flat_map(&:clauses)
      defaulted = clauses.count { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
      if defaulted.positive?
        pct = (defaulted * 100.0 / clauses.size).round(1)
        warn "[WARN] #{defaulted}/#{clauses.size} clauses (#{pct}%) carry fallback/stub values — see the Data " \
          "Quality section."
      end

      puts "\nGenerated:"
      paths.each { |format, path| puts "  #{format.to_s.upcase}: #{path}" }
    end
    # rubocop:enable Metrics/AbcSize
  end
  # rubocop:enable Metrics/ModuleLength
end
