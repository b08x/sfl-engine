# SFL Compiler — Rebuild Blueprint

**Target:** `/home/b08x/WorkspaceV3/sfl-compiler` (sfl-compiler v0.1.0, Ruby >= 3.4)
**Method:** ruby-dev pipeline — `sift` (audit) → `analyse` (diagnosis) → architecture per `ood-principles.md` → `perf` (measurement plan) → phased backlog.
**Evidence base:** `lib/` (104 files, 13,672 LOC), `spec/` (80 spec files, ~12,600 LOC, 838 examples), `exe/`, `scripts/`, `ext/`, `Gemfile`, `sfl-compiler.gemspec`, `config.ru`. Prior analyses (`docs/`, `CLAUDE.md`, `.claude/`, `.opencode/`) were deliberately not consulted.

**Toolchain caveat:** static checks ran under a sandbox Ruby 3.0.2 while the project pins 3.4.4 (`.ruby-version`). A full `ruby -c` sweep produced 49 "failures", **all** of which are Ruby 3.1+ hash value-omission (`{ turn_id:, total: }`) or 3.2+ anonymous `**` forwarding — valid syntax on the target Ruby. No genuine syntax errors were found.

---

## 1. SIFT Audit

### Scores

| Dimension | Weight | Score | Rationale (summary) |
|---|---|---|---|
| Structure | 0.25 | **55** | Monolithic gem with ~44 runtime deps spanning 7 delivery surfaces; split-brain loading (Zeitwerk + manifest `require_relative` + inline `require`); multi-constant files; two competing config surfaces |
| Idioms | 0.20 | **62** | Consistent frozen literals, kwargs, Dry::Struct — but `rescue Exception`, nested `Timeout.timeout`, `define_singleton_method` monkey-patching of dependency internals, a 3-deep `method_missing` proxy chain, 846-line and 627-line files |
| Functionality | 0.35 | **58** | Two confirmed correctness bugs (Pass 1 head resolution, API async schema mismatch); silent-data-mangling heuristics; a GC-timing workaround load-bearing for VM stability; numeric drift between duplicated implementations |
| Testing | 0.20 | **68** | 838 examples with good unit discipline — but `spec/integration/` cannot even load (requires a deleted file), two parallel spec roots, duplicate spec files, SimpleCov present but never started, CLI `run_*` and PassOneEngine untested |

**Overall: (55×0.25) + (62×0.20) + (58×0.35) + (68×0.20) = 60.1 → "Functional but requires refactoring."**
The rebuild premise is justified: the pipeline core is sound and well-typed, but the load-bearing walls (packaging, loading, concurrency posture, duplication) cannot be renovated in place without touching nearly every file.

---

### Structure findings

#### S1 — One gem, seven products (Critical)

- **Claim:** The gem violates single responsibility at the package level.
- **Data:** `sfl-compiler.gemspec:35-77` declares runtime dependencies for a TUI (`bubbletea`, `bubbles`, `lipgloss`, `glamour`, `gum`, `pastel`, `tty-*`), a desktop GUI (`glimmer-dsl-libui`), an HTTP server (`falcon`), a distributed job system (`sidekiq`, `gush`), topic modeling (`tomoto`), ONNX inference (`informers`, `onnxruntime`), OpenTelemetry, and the actual NLP pipeline (`ruby-spacy`, `dspy`, `sequel`, `pgvector`). `lib/` contains `chat/`, `tui/`, `review_gui/`, `api/`, `jobs/`, `workflows/` alongside the pipeline. `spec.executables = %w[sfl-analyze sfl-api sfl-review]` (`gemspec:32`).
- **Warrant:** SRP ("describe the class's job without 'and'") applies to gems too; TRUE's *Usable* quality — a consumer wanting clause compilation must install libui system libraries and a Go-derived TUI stack.
- **Backing:** `gem install sfl-compiler` also triggers `ext/sfl_compiler/extconf.rb`, which downloads a Python toolchain (see S5) — the install cost of the heaviest consumer is imposed on every consumer.
- **Qualifier:** Critical for a rebuild; harmless for a single-user research repo.
- **Rebuttal:** If this is forever a personal research vehicle, one gem is simpler. But the gemspec's `allowed_push_host: rubygems.org` and MFA metadata signal publishing intent.

#### S2 — Split-brain code loading (Critical)

- **Claim:** Three loading regimes coexist, and adding a file to the wrong directory silently fails.
- **Data:** `lib/sfl/compiler.rb:105-143` — Zeitwerk with 7 inflection overrides, 6 `collapse` calls (`pass_one/`, `pass_two/`, `storage/`, `retrieval/`, `jobs/`, `workflows/` → flat constants) and 7 `ignore` calls (`analysis/`, `formatters/`, `chat/`, `tui/`, `api/`, `review_gui/` → loaded only via manifest files `analysis.rb` / `formatters.rb` etc. through `require_relative`). Meanwhile `cli.rb:6` does a raw `require_relative "retrieval/hybrid_retriever"` into a Zeitwerk-collapsed directory, and `langfuse_reachability.rb` must be required *before* the gem itself (`exe/sfl-analyze:27`, `config.ru:17`).
- **Warrant:** TRUE's *Transparent* — the consequence of adding `lib/sfl/compiler/analysis/new_thing.rb` is an `uninitialized constant` at runtime unless a second file (`analysis.rb`) is also edited; the file system no longer predicts the constant table.
- **Backing:** The same file, `compiler.rb:130-135`, carries a comment block explaining why `collapse` cannot be used for these directories — the config documents its own inconsistency.
- **Qualifier:** Critical. This is the single largest source of "works on my machine" loading fragility.
- **Rebuttal:** The manifests do work today, and eager manifest loading avoids autoload-in-thread issues. But the same benefit is available uniformly via `loader.eager_load` with conventional paths.

#### S3 — Multi-constant files break autoload addressing (High)

- **Claim:** Several files define constants that Zeitwerk cannot autoload by name.
- **Data:** `pass_two/pass_two_engine.rb` defines **7** top-level-namespace constants (`PassTwoEngine`, `PremiseOutput`, `SFLSignature`, `SFLAnnotator`, `ClauseAnnotation`, `SFLBatchSignature`, `SFLBatchAnnotator` — lines 19, 654, 665, 708, 769, 786, 808). `retrieval/context_synthesizer.rb` defines 3 (`ContextSynthesizer`, `SynthesisSignature`, `SFLSynthesizer`). `bootstrap.rb` defines 4 (`Bootstrap`, `SafeOpenAIClientProxy`, `SafeChatProxy`, `SafeCompletionsProxy` — lines 25, 237, 257, 277). `storage/database.rb` defines 3 (`Database`, `Migrator`, `ColumnBackfill`).
- **Warrant:** Zeitwerk contract: one file ↔ one constant. A reference to `SFL::Compiler::SFLSynthesizer` before anything touches `ContextSynthesizer` raises `NameError`; the code only works because callers happen to load the primary constant first.
- **Qualifier:** High — latent NameError, plus it makes the 846-line `pass_two_engine.rb` inevitable.
- **Rebuttal:** Signature classes genuinely belong near their engine; the fix is a directory (`pass_two/signatures/`), not cohabitation.

#### S4 — Two competing configuration surfaces; ENV read at require time (High)

- **Claim:** The stated design "library never reads ENV — only entry points call Bootstrap" (`bootstrap.rb:23-24`) is contradicted by the code.
- **Data:** `Configuration#initialize` reads six ENV vars at object creation (`compiler.rb:87-95`). `PassTwoEngine` reads four ENV vars **into class constants at require time** (`pass_two_engine.rb:25-48`) and two more per instance (`:195-196`). `Embedder#configure_ruby_llm` reads `OLLAMA_BASE_URL` (`embedder.rb:44`). `CognitiveGas` reads `COGNITIVE_GAS_BUDGET` (`cognitive_gas.rb:42`). `ThemeRhemeExtractor` reads `OPENROUTER_API_KEY` (`theme_rheme_extractor.rb:144`).
- **Warrant:** Metz dependency checklist — these classes now depend on process-global mutable state; and require-time ENV capture means `Dotenv.load` ordering silently changes behavior (the codebase already fights this: the Langfuse pre-flight dance in `exe/sfl-analyze:13-35` and `bootstrap.rb:8-17` exists *because* of require-time ENV capture in a dependency).
- **Qualifier:** High. `SFL_BATCH_SIZE` set in `.env` but not the shell is ignored, because the constant froze before `Dotenv.load` ran — the exact bug class the Bootstrap comment claims to prevent.

#### S5 — Install-time network scripting in `extconf.rb` (High)

- **Claim:** Packaging correctness depends on a fake native extension running `curl | sh`.
- **Data:** `ext/sfl_compiler/extconf.rb` has no C: it writes a stub Makefile (`:49-54`), installs `uv` via `curl -LsSf https://astral.sh/uv/install.sh | sh` if absent (`:77`), provisions CPython 3.12 and `pip install spacy click "numpy<2"` into `vendor/python` (`:117-118`). `bootstrap.rb:96-105` then mutates `ENV["PYTHON"]`/`ENV["PYTHONPATH"]` at runtime.
- **Warrant:** Bundler never runs extensions for path-sourced gems (this repo's own dev setup), so the vendored env exists only under `gem install` — two install paths, two behaviors. Piping remote shell scripts inside `gem install` is also a supply-chain liability.
- **Qualifier:** High. Note the comment in `exe/sfl-analyze:4-5` claims "the Gemfile doesn't use `gemspec`" while `Gemfile:5` is literally `gemspec` and `Gemfile.lock` lists the PATH source — the packaging story has drifted even in its own comments.
- **Rebuttal:** Vendoring Python at install time is a defensible answer to "spaCy missing at runtime"; the objection is to *where* (extconf) and *how* (curl|sh, ENV mutation), not to vendoring per se.

#### S6 — Global JSON monkey-patch at require (Medium)

- **Claim:** Requiring the gem swaps the process-wide JSON implementation.
- **Data:** `lib/sfl-compiler.rb:3` — `require "yajl/json_gem"`, which redefines `JSON.parse`/`JSON.generate` globally (yajl-ruby's documented json_gem compatibility mode).
- **Warrant:** TRUE's *Exemplary*; a library must not alter global behavior of a stdlib for its host process.
- **Qualifier:** Medium (silent behavior/precision differences in any embedding app).

---

### Idioms findings

#### I1 — Reflection into dependency internals (High)

- **Claim:** Bootstrap patches private internals of DSPy adapters via reflection.
- **Data:** `bootstrap.rb:140-151` (`instance_variable_get(:@adapter)`, `define_singleton_method(:prepare_chat_instance)`), `:163-172` (`instance_variable_get(:@client)`, `instance_variable_set(:@client, SafeOpenAIClientProxy.new(...))`), plus a three-level `method_missing` proxy chain (`SafeOpenAIClientProxy` → `SafeChatProxy` → `SafeCompletionsProxy`, `:237-324`).
- **Warrant:** Metz dependency checklist item 2 — knowing the names of messages sent to *someone else's private objects* is maximal coupling; any dspy-openai minor release can break this silently.
- **Qualifier:** High. The proxies exist to add a timeout and nil-checking the adapter doesn't expose; that is an upstream-contribution or adapter-wrapper problem, not a `method_missing` problem.

#### I2 — `rescue Exception` and thread-killing timeouts (High)

- **Data:** `pass_two_engine.rb:217` (`rescue Exception` inside the hand-built circuit breaker); `Timeout.timeout` used at two nested layers for the same call — inside the breaker singleton (`:211`) *and* in `call_with_watchdog` (`:366`).
- **Warrant:** `rescue Exception` traps `Interrupt`/`SystemExit`/`NoMemoryError`; `Timeout.timeout` kills threads at arbitrary points and is documented-unsafe around native calls — the codebase simultaneously fears this (PyCall comments) and doubles down on it.
- **Qualifier:** High.

#### I3 — Serialize-then-parse round trip to the LLM layer (Medium)

- **Data:** `PassTwoEngine#format_syntactic_context` renders clause data into a prose string (`pass_two_engine.rb:550-562`); the single-clause `SFLAnnotator#parse_context` then **regex-splits that same string back into fields** (`:738-760`) to build signature inputs.
- **Warrant:** Muda (overprocessing) + Demeter: the annotator should receive the structured inputs directly; a `Text: foo: bar` clause text containing a colon corrupts the parse.
- **Qualifier:** Medium (the batch path only formats; the parse leg is the single-clause path).

#### I4 — God files (Medium)

- **Data:** `pass_two_engine.rb` 846 lines / 7 classes; `cli.rb` 627 lines (parsing + 7 `run_*` wiring methods + signal handling + report printing); `documentation_analyzer.rb` 509; `conversation_analyzer.rb` 490; `clause_repository.rb` 435 (CRUD + review queue + Pass-1 reconstruction).
- **Warrant:** SRP; CLI already admits the tension ("owns argv parsing, terminal output, and exit codes — and nothing else", `cli.rb:10-12` — yet builds pipelines, embedders, traps signals, and formats reports).

#### I5 — Logger instantiation scattered (Low)

- **Data:** 15+ classes each construct `Journald::Logger.new("sfl-compiler-…")` in `initialize` (pipeline.rb:31, pass_one_engine.rb:24, ideational_extractor.rb:47, clause_repository.rb:39, hybrid_retriever.rb:21, embedder.rb:16, …); 13 more sites bypass it with bare `warn "[WARN] …"` to stderr (pass_two_engine.rb:646, subtitle_loader.rb:59,90,129,135, knowledge_base_analyzer.rb:80,136, narrative_generator.rb:432, image_loader.rb:73, context_synthesizer.rb:80, provider_fallback.rb:43).
- **Warrant:** Dependency injection; journald is a hard systemd coupling every consumer inherits, and the stderr channel is un-silenceable in library contexts.

---

### Functionality findings

#### F1 — Pass 1 head-index resolution is wrong for repeated tokens (Critical, correctness bug)

- **Claim:** The dependency graph emitted by Pass 1 is corrupted whenever a sentence repeats a word.
- **Data:** `pass_one_engine.rb:110-126`:
  ```ruby
  local_idx = {}
  raw = []
  sent.each do |token|
    next if token.text.strip.empty?
    local_idx[token.text] ||= raw.length   # keyed by TEXT
    raw << token
  end
  ...
  head_idx = ... local_idx[token.head.text] || -1
  ```
  Head resolution is keyed on **token text**. In "the dog chased the cat", both "the" tokens' dependents resolve their head to the *first* "the" (index 0). Any duplicated word (articles, pronouns, repeated verbs) mis-links `head_index`.
- **Warrant:** `SyntacticToken#head_index` is stored (`clause_repository.rb:62`), fed to the ideational extractor's transitivity hash, and persisted into `raw_transitivity` — downstream data is silently wrong.
- **Backing:** spaCy tokens expose a positional index (`token.i`); a subtraction against `sent.start` gives the correct sentence-local head index with no text lookup at all. Also note `local_idx[token.head.text] == token.text` is used to detect ROOT (`:122`) — a token whose head is a *different* token with identical text is falsely marked ROOT.
- **Qualifier:** Critical for anything consuming the tree; the transitivity classifier mostly reads `dep` labels so surface reports partially mask it.

#### F2 — API async compile writes a schema no consumer reads (High, dead endpoint)

- **Claim:** `POST /pipeline/compile` with `sync: false` silently does nothing.
- **Data:** `api/server.rb:121-123` writes the temp JSONL as `{speaker:, timestamp:, message:}`; `ConversationAnalyzer.load_jsonl` keeps only lines where `turn[:mes]` is present (`conversation_analyzer.rb:60-67`); `ConversationAnalysisWorkflow#configure` calls `load_jsonl` directly (`conversation_analysis_workflow.rb:25`), so `raw_turns == []`, zero `CompileTurnJob`s are enqueued, and the workflow "succeeds" with an empty reduce.
- **Warrant:** Root-cause: two producers of the turn schema with no shared constructor — the schema (`name`/`mes`/`send_date`) lives as tribal knowledge in five places (analyzer, subtitle loader, three export loaders).
- **Qualifier:** High. Also note `/tmp` files are never cleaned up (`:121`).

#### F3 — VM stability depends on a `GC.start` placed between passes (Critical, design debt)

- **Claim:** The orchestrator carries a manual GC invocation to avoid a PyCall GIL/GVL deadlock, and the underlying constraint is structural, not fixed.
- **Data:** `pipeline.rb:72-76`: "Sweep Pass 1's dead PyCall wrappers NOW, on this thread. If GC instead triggers on a Pass 2 worker, pycall_pyptr_free blocks on the Python GIL while holding the GVL — deadlocking the whole VM". Pass 2 then runs `Thread.new` workers (`pass_two_engine.rb:479-498`). `CompileTurnJob:14-19` and `tui/batch_app.rb:10-12` document the same class of failure ("unlike TUI::BatchApp's broken --live view"); `review_gui/app.rb:77` still spawns a `Thread.new` in a process family that may touch PyCall.
- **Warrant:** Five-Whys lands on the systemic root: **PyCall objects and Ruby threads share one process by design**. `GC.start` narrows the window; any future GC trigger point (allocation spike inside a worker) reopens it. Correctness-by-GC-timing is not a property a rebuild may carry forward.
- **Qualifier:** Critical (a live crash class: observed and documented in-code).

#### F4 — Duplicated `mean` re-diverged in the job layer (High, silent numeric drift)

- **Claim:** The drift that `Analysis::Aggregations` was created to end still exists between the inline and distributed paths.
- **Data:** `aggregations.rb:6-19` ("Extracted from 4 independent copies … two defaulted to 0.0, two to 0.5 … Standardized on 0.5 … consistent 3-decimal rounding") vs `jobs/compile_turn_job.rb:95-99`:
  ```ruby
  private def mean(values)
    return 0.0 if values.empty?
    values.sum / values.size.to_f    # no rounding
  end
  ```
- **Warrant:** The same conversation analyzed inline (`sfl-analyze conversation`) vs via `--live`/Gush yields different `avg_tenor`/`avg_modality` for empty-clause turns (0.5 vs 0.0) and different rounding everywhere. DRY violated exactly where it bites: numerics feeding reports.
- **Qualifier:** High. `Types::ConversationTurn` constrains `avg_tenor` to 0-1 so 0.0 passes validation silently.

#### F5 — In-place mutation + deep rebuild in TenorTracker (Medium)

- **Data:** `tenor_tracker.rb:16-24` replaces elements of the **caller's** array (`turns[idx] = turn.class.new(**turn.to_h.merge(...))`). `Dry::Struct#to_h` is deep, so every turn's full clause tree (tokens, payloads) is hash-ified and re-validated just to set one float. `detect_significant_shifts` (`:35`) indexes `turns[turn.turn_id - 2]`, assuming `turn_id` equals position+1 — false after any filtered/partial turn list.
- **Warrant:** Metz on mutation visibility (callers passing their only reference see it change); the correct idiom is the shallow `Dry::Struct#new(tenor_shift: shift)` partial-update already used elsewhere (`documentation_analyzer.rb:370, 382`).

#### F6 — `clamp01` silently rescales out-of-range LLM values by guessing the scale (Medium)

- **Data:** `pass_two_engine.rb:604-611`: any value > 1.0 is divided by 5 then clamped. A model answering on a 0-10 scale returns 10 → 2.0 → clamped to 1.0; a slightly-out-of-range 1.5 (meant as ~1.0) becomes 0.3 — inverting the signal.
- **Warrant:** Fail-fast beats guess-and-mangle: out-of-contract values should be rejected → retry → provenance-marked fallback, the ladder that already exists.

#### F7 — Persistence is per-clause transactions with no bulk path (Medium)

- **Data:** `pipeline.rb:94-98` loops `annotated.each { @clause_repo.store(ac) }`; each `store` opens its own transaction and performs 3 inserts (`clause_repository.rb:54-95`); embeddings are then generated and inserted one row at a time (`pipeline.rb:101-105`). A 500-clause document = 500 transactions, 1,500+ round trips, 500 sequential Ollama HTTP calls.
- **Warrant:** Muda (waiting); Sequel's `multi_insert`/`import` exists precisely for this. Also: no FK constraints anywhere (`database.rb:193` admits "No FK … same convention"), so partial deletes can orphan payload rows without the DB noticing.

#### F8 — Retrieval filters discard recall instead of constraining the query (Medium)

- **Data:** `hybrid_retriever.rb:52-64` fetches `limit*3` candidates from each arm, merges via RRF, **then** filters in Ruby (`apply_filters`, `:166-208` — three extra queries, then row-by-row predicate checks). A selective filter (e.g. `mood: "interrogative"`) can eliminate all 30 candidates while thousands of matching rows exist beyond the cutoff — silent recall loss, not just inefficiency.
- **Warrant:** Push predicates into the SQL of both arms (both are single-table/joinable queries; `find_all`'s `FIND_ALL_FILTERS` at `clause_repository.rb:291-301` already demonstrates the joined pattern).

#### F9 — Per-job re-bootstrap in the distributed path (Medium)

- **Data:** `CompileTurnJob#pipeline` (`compile_turn_job.rb:88-93`) runs `Bootstrap.call(require_db: true, …)` — which re-runs `Migrator.run_all` (`bootstrap.rb:225-233`) — and constructs a fresh `Pipeline` (→ `Spacy::Language.new`, a multi-second model load) **per job instance**, i.e. per turn. `sidekiq_boot.rb:17-22` deliberately boots with everything off, deferring to per-job wiring.
- **Warrant:** Muda (overprocessing): N turns → N schema migration passes + N spaCy model loads per worker process lifetime instead of 1.

#### F10 — Cache double-read in resume mode (Low)

- **Data:** `pipeline.rb:173-217`: `@cache.partition` reads every cache file once; the merge loop then calls `@cache.fetch(document_id, clause)` **again** for every pair — each hit is parsed from disk twice per run (`pipeline_cache.rb:38-47`).

#### F11 — Embedder failures produce silent permanent gaps (Low)

- **Data:** `embedder.rb:24-41` returns `nil` on any error (circuit open, HTTP failure); `pipeline.rb:103-104` skips storage on nil with no warning, no retry queue, no provenance. Clauses simply never appear in semantic search, and nothing reports it.

---

### Testing findings

#### T1 — `spec/integration/` cannot load (High)

- **Data:** `spec/integration/conversation_analysis_spec.rb:4` — `require_relative "../../scripts/sfl_analysis/templates/conversation_analysis_template"`; `scripts/sfl_analysis/` **does not exist** (verified: `scripts/` contains 5 files, no subdirectory). Plain `bundle exec rspec spec/` dies with LoadError before running anything. The file is also API-rotten: `integration_env_ready?` is defined as `def self.` (`:126`) but called from `before(:all)` instance context (`:13`); tests call `analyzer.load_jsonl` (now a class method, `conversation_analyzer.rb:60`) and `analyze_conversation` (no such method — it's `analyze`); `described_class.new` omits the now-required pipeline wiring.
- **Warrant:** A suite that requires an exclude-pattern incantation to run is a broken quality gate (Testing Grid preamble: the suite's first job is to run).

#### T2 — Two spec roots, duplicate spec files (Medium)

- **Data:** `spec/sfl/compiler/**` and `spec/sfl_compiler/**` both exist (the latter holds formatters/tenor/speaker/correlation specs). `spec/sfl/compiler/pass_two_engine_spec.rb` (232 lines) **and** `spec/sfl/compiler/pass_two/pass_two_engine_spec.rb` (482 lines) both describe `SFL::Compiler::PassTwoEngine`.
- **Warrant:** Drift by duplication — expectations diverge between copies; discoverability breaks.

#### T3 — Coverage tooling installed but disconnected (Medium)

- **Data:** `simplecov` in `Gemfile:29` (quality group); `spec/spec_helper.rb` never requires or starts it. No coverage threshold exists.

#### T4 — Untested seams are exactly the risky ones (Medium)

- **Data:** No spec exists for `PassOneEngine` (the file with bug F1 — `spec/sfl/compiler/pass_one/` contains only `ideational_extractor_spec.rb`), `Embedder`, `chat/*`, `tui/wizards/*`, or any `CLI.run_*` path (only `CLI.parse` is covered, `cli_spec.rb`).
- **Warrant:** Metz Testing Grid: `PassOneEngine#process` is an incoming message whose *result* (token indices, head links) is assertable with a stubbed spaCy double — no Python needed; its absence is why F1 survived.
- **Rebuttal:** `run_*` methods genuinely need DB+LLM for full verification, but their *wiring* (which analyzer, which repos, which flags) is assertable with verified doubles.

---

## 2. Diagnosis — what the rebuild must not carry forward

(analyse skill: Gemba findings keyed for handoff; each maps to backlog items in §5.)

### D1 `five-whys:systemic` — PyCall-in-process as the concurrency root disease
**Symptom chain:** segfault under threads → `-c 1` worker requirement → `GC.start` in `Pipeline#compile` (F3) → interrupt-masking around `Pipeline.new` (`cli.rb:578-583`, because CPython raises raw `Interrupt` past Ruby traps) → an entire Gush/Sidekiq subsystem built to obtain process isolation → a TUI that may only *poll Redis* because it can't share a process with spaCy.
**Root:** embedding a non-thread-safe foreign interpreter inside the orchestrating Ruby process. Every workaround above is a symptom tax. **Rebuild rule:** Pass 1 runs behind a process boundary (sidecar), never in the orchestrator's address space.

### D2 `muda:duplication` — the analyzer family is one engine written four times
`ConversationAnalyzer` and `DocumentationAnalyzer` duplicate, near-verbatim: the topic pre-pass stub-turn block (conversation_analyzer.rb:109-131 ↔ documentation_analyzer.rb:65-87), compile loop with stop/progress plumbing (:133-146 ↔ :89-102), `detect_key_moments` (:191-252 ↔ :218-249), `detect_example_passages` (:254-306 ↔ :251-279), `tenor_timeline`/`timeline` (:399-409 ↔ :455-465), `field_evolution` (:411-419 ↔ :467-475), `topic_evolution` (:421-432 ↔ :477-488), `report_progress` (:308-317 ↔ :444-453), `topic_k` (:484-486 ↔ :389-391). `CompileTurnJob` re-implements `compile_turn` a third time (F4), and `KnowledgeBaseAnalyzer` orbits the same shapes. ≈350 duplicated lines whose copies have **already** drifted numerically once.

### D3 `muda:overprocessing` — data shape churn
Object → prose string → regex parse (I3); struct → deep `to_h` → re-validate for one field (F5); result → `JSON.generate` → `JSON.parse(symbolize_names:)` → struct **in-process** (`cli.rb:309-311, 370-372` — a self-round-trip used as a deep-symbolize); cache files parsed twice per resume (F10); `Types.dump`/`load_*` hand-rolled Time coercion (`types.rb:22-91`) instead of a serialization boundary type.

### D4 `root-cause:schema-tribal` — the turn schema has no owner
`{name:, mes:, send_date:}` is independently produced/consumed by `ConversationAnalyzer.load_jsonl`, `SubtitleLoader`, `ClaudeExportLoader`, `ChatGPTExportLoader`, `MistralExportLoader`, and (wrongly — F2) `API::Server#compile_pipeline`. The rebuild needs a `Turn` value type with one constructor that every producer must go through, making F2-class bugs unrepresentable.

### D5 `muda:waiting` — database chatter patterns
Per-clause transactions (F7), post-hoc Ruby filtering with recall loss (F8), per-job migrations and model loads (F9), one-at-a-time embedding HTTP calls (F7), `delete_by_document`-then-insert idempotency living in *caller* convention (`conversation_analyzer.rb:371`, `documentation_analyzer.rb:394`) rather than in the repository, no FKs.

### D6 `pattern:reflection-coupling` — dependency internals as API
`instance_variable_get/set` + `define_singleton_method` into DSPy adapters, `method_missing` proxy chain, hand-built circuit breaker via `define_singleton_method` on a `CircuitHandler` with `rescue Exception` (I1, I2). Three different circuit-breaker mechanisms coexist: the `circuit_breaker` gem DSL (Embedder), the hand-wrapped `CircuitHandler` (PassTwoEngine), and the duck-typed `CognitiveGas` budget — none injected at a common seam.

### D7 `root-cause:loading` — split-brain loading + require-time side effects
S2 + S4 + the Langfuse pre-flight (`langfuse_reachability` must load before the gem; `config.ru` and `exe/sfl-analyze` each re-implement the dance) + `yajl/json_gem` global patch (S6) + `Sequel.extension :fiber_concurrency` executed at class-body load (`database.rb:25` — a process-global switch flipped by requiring a file).

### D8 `muda:inventory` — experimental cargo in the production tree
`question_graph.rb` (Gödel-encoded DAG whose BIGINT overflow "is the thesis"), `cognitive_gas.rb` (injectable nowhere by default), `convergence_detector.rb`, `derivation_hash.rb`, GEB sprint jobs (`sprint_role_job.rb`, `crab_constraint_job.rb`, `intermediate_genie_job.rb`, `sprint_workflow.rb`), `narrative_self_analyzer.rb` ("strange-loop"), `--sprint-id` CLI surface, `chat/`, `review_gui/` (glimmer GUI), `theme_rheme_extractor.rb` (marked experimental). These inflate the gemspec (S1), the loader config (S2), and the maintenance surface. `experiments/` already exists as the right home.

### D9 `root-cause:silent-degradation` — failure paths that under-report
Embedder nil-gaps (F11); `clamp01` scale-guessing (F6); `default_interpersonal` hardcodes `reasoning: "Circuit breaker open — defaults applied"` even when the actual cause was a timeout or provider exhaustion (`pass_two_engine.rb:579-589` — forensics lie); `Database.setup_extensions` and `create_indices` swallow failures into warn-level logs (`database.rb:40-46, 254-260`) so a missing pgvector extension surfaces later as a cryptic insert error. The *provenance-marking* ladder itself (fallback/stub/chunk_artifact + Data Quality reporting) is genuinely good and must be preserved — but with truthful reasons.

---

## 3. Rebuild Architecture

### 3.1 Package topology (fixes S1, S5, D8)

Scaffold with `gemsmith --max` per gem (scaffold skill, "Ruby gem (library)" archetype), one repo, four gems + one quarantine:

```
sfl/
├── sfl-core/          # types, ports, pass1 client, pass2 engine, pipeline, loaders
│   └── deps: dry-struct, dry-types, dry-monads, zeitwerk, pragmatic_tokenizer, inkmark
├── sfl-store/         # Sequel/pg/pgvector: repositories, migrations, retrieval
│   └── deps: sfl-core, sequel, pg, pgvector
├── sfl-llm/           # DSPy signatures/annotators, provider chain, embedder adapters
│   └── deps: sfl-core, dspy, ruby_llm
├── sfl-cli/           # exe/sfl-analyze, formatters, analyzers-as-application-services
│   └── deps: sfl-core, sfl-store, sfl-llm, tty-progressbar, optparse
└── experiments/       # question_graph, cognitive_gas, GEB jobs, chat, review_gui,
                       # narrative_self_analyzer, theme_rheme — not shipped
```

TUI (`bubbletea` stack), HTTP API (`falcon`), and Sidekiq/Gush jobs are **optional add-on gems** (`sfl-tui`, `sfl-api`, `sfl-jobs`) or deleted per §5 decisions — none of their dependencies appear in `sfl-core`.

*Warrant:* SRP at package granularity; **dependency direction rule** — every arrow points at `sfl-core`, which depends only on things that change less often than the product (dry-rb, stdlib). A consumer embedding clause compilation pays for zero TUI/GUI/server code.

**Python packaging:** drop the extconf pseudo-extension. `sfl-core` ships a `sfl doctor`/`sfl setup-python` command that provisions the sidecar env explicitly (uv if present, clear error otherwise) and a documented `SFL_PYTHON` override. Install-time network access: gone (S5).

### 3.2 Loading & configuration (fixes S2, S3, S4, S6, D7)

- **One constant per file, uniform nesting, zero `collapse`, zero manifests.** `SFL::Core::PassTwo::Engine` lives at `lib/sfl/core/pass_two/engine.rb`. DSPy signatures get their own files (`pass_two/signatures/batch_annotation.rb`). Inflector overrides shrink to acronyms only (`CLI`, `TUI`, `SFL`). *Warrant:* Zeitwerk contract = Transparent + Exemplary; the filesystem is the constant table again.
- **Composition root pattern.** Exactly one module (`SFL::CLI::Boot` per entry point, delegating to `SFL::Core::Config.from_env(env)`) reads ENV, exactly once, at *call* time — never at require time. All tunables (`batch_size`, `concurrency`, `chunk_timeout`, `batch_attempts`, breaker thresholds, ollama URL) become fields on an immutable `Config` (`Data.define`), injected as keyword args. Delete `Configuration`-reads-ENV (compiler.rb:87-95) and every class-body `ENV.fetch`. *Warrant:* Metz dependency checklist remedy 1 (inject); kills the Dotenv-ordering bug class, which also dissolves the Langfuse pre-flight dance — tracing is configured explicitly by the composition root, not by a require-order ritual.
- No global patches: `yajl/json_gem` out (use `JSON` or pass yajl explicitly at the one hot serialization site if profiling justifies it — §4); `Sequel.extension :fiber_concurrency` moves into `sfl-api`'s boot (the only fiber-concurrent entry point), not a class body in `sfl-store`.

### 3.3 Ports & adapters for every volatile boundary (fixes D1, D6, I1, F11)

Define small duck-typed ports in `sfl-core`; adapters live in the satellite gems. *Warrant:* **duck typing** ("objects are their public interfaces") + dependency checklist — the engine knows one message per collaborator:

| Port (duck) | Messages | Adapters |
|---|---|---|
| `SyntacticParser` | `parse(text) → Result<[SyntacticClause]>` | `SpacySidecarParser` (default — see below), `FakeParser` (tests) |
| `Annotator` | `annotate(batch) → Result<[Annotation]>` | `DspyBatchAnnotator`, `FakeAnnotator` |
| `Embedder` | `embed(texts) → Result<[vector]>` (batched, plural) | `OllamaEmbedder`, `NullEmbedder` |
| `ClauseStore` | `replace_document(doc_id, clauses)`, `find_…` | `PgClauseStore`, `MemoryClauseStore` |
| `Cache` | `fetch_all(keys)`, `store_all(pairs)` | `DiskCache`, `NullCache` |
| `Breaker` | `call { } → raises Open` | `CircuitBreakerAdapter`, `CognitiveGasAdapter`, `NullBreaker` |
| `Instrumenter` | `event(name, **fields)` | `JournaldInstrumenter`, `IoInstrumenter`, `NullInstrumenter` |
| `ProgressSink` | `turn_started`, `turn_finished`, `chunk_done` | CLI printer, TUI feed, Null |

Consequences:

- **`SpacySidecarParser` is the D1 fix.** Pass 1 becomes a long-lived Python subprocess (spaCy loaded once) speaking NDJSON over stdin/stdout (or a localhost socket). The Ruby process contains **no PyCall**: no GVL/GIL deadlock, no `GC.start` (deleted from `Pipeline`), no interrupt masking, no `-c 1` Sidekiq constraint, threads and fibers become safe everywhere, and the TUI may run analysis in-process again. The sidecar also structurally fixes F1 because the protocol carries spaCy's positional `token.i`-derived head indices computed on the Python side, where they're native. (Rebuttal: a sidecar adds a process to manage — accepted; the current design *already* pays a whole Redis+Sidekiq topology for the same isolation.)
- **One breaker seam.** The three current mechanisms collapse into the `Breaker` port; the DSPy timeout moves to the HTTP client config (already half-done in `apply_request_timeout`) — contributed upstream or wrapped in a plain adapter object with explicit methods, deleting the `method_missing` proxy chain and both `Timeout.timeout` layers (I1, I2).
- **Instrumenter port** replaces 15 `Journald::Logger.new` sites and 13 bare `warn`s (I5, D9): libraries emit events; entry points decide the sink.

### 3.4 One analysis engine, many sources (fixes D2, D4, F4)

```ruby
# The duck every input format implements:
class ConversationSource   # .jsonl + subtitle + export loaders behind it
  def units → [Unit]       # Unit = Data.define(:id, :actor, :timestamp, :text, :document_id)
  def labels → {unit:, actor:, actors_list:}
end
class DocumentationSource  # markdown/PDF sections
class KnowledgeBaseSource  # KB artifacts
```

A single `Analysis::Engine` owns the loop (stop-flag, progress, topic pre-pass, compile, aggregate) and the shared derivations (`key_moments`, `example_passages`, `timeline`, `field_evolution`, `topic_evolution`) — written **once**. Source-specific analysis (chunk-artifact detection, sprint footers, KB scoring) attaches as composed post-processors, not subclass copies. `Turn`/`Unit` construction happens in exactly one place, so the schema is owned (D4) and the Gush job path calls the *same* `Engine#compile_unit` the inline path uses — F4-class drift becomes impossible because there is no second implementation. *Warrant:* composition bias (Metz relationship table); Template-Method-with-hooks only if a genuine algorithm skeleton emerges — default is composed collaborators.

All aggregation math lives in one `Aggregations` module used by engine, profiler, correlator, **and jobs**; property test pins `mean([]) == 0.5` and rounding.

### 3.5 Immutability and data flow (fixes F5, D3)

- Value objects via `Dry::Struct` (kept — the typing discipline is a genuine strength of the current code) with **shallow** updates only: `turn.new(tenor_shift: x)` — never `Klass.new(**struct.to_h.merge(...))`.
- `TenorShifts.annotate(turns) → [Turn]` returns a new array; no method mutates caller-owned collections (Metz: Transparent).
- Annotator receives structured input structs directly; the prose formatting lives only inside the DSPy adapter as its prompt-rendering concern; the regex `parse_context` leg is deleted (I3).
- One serialization boundary: `SFL::Core::Wire.dump/load` (the current `Types.dump`/`load_*`, consolidated and round-trip property-tested) used by cache, Gush payloads, and API alike. The CLI's `JSON.parse(JSON.generate(x))` deep-symbolize disappears because `Wire.load` accepts the poller's already-parsed hash.

### 3.6 Storage & retrieval (fixes F7, F8, D5)

- **Sequel's migration framework** (versioned files under `sfl-store/db/migrations/`) replaces `Migrator` + `ColumnBackfill`; migrations run via CLI task, not on every boot/job. Real FKs (`ideational_payloads.clause_id → clauses.external_id`, etc.) with `ON DELETE CASCADE` — `delete_by_document` becomes one statement, and orphan states become impossible.
- `ClauseStore#replace_document(doc_id, clauses)`: one transaction, `multi_insert` for clauses/payloads/embeddings — idempotency is the repository's contract, not a caller convention.
- Retrieval: scalar filters compiled into the SQL of both search arms (reusing the `FIND_ALL_FILTERS` lambda-table pattern from `clause_repository.rb:291-301`); RRF merge stays in Ruby (it's rank arithmetic over ≤60 rows). Fixes the recall loss and deletes three post-hoc queries per retrieve.
- Embeddings: batched `embed(texts)` (Ollama supports batch inputs) + an `embedding_status` provenance column so gaps are visible and re-driveable (F11/D9).

### 3.7 Error policy (fixes I2, F6, D9)

- `dry-monads` Result at stage boundaries (already a dependency; orchestrator mandate 3): `parser.parse → Success([clauses]) | Failure(ParseError)`; pipeline degradation ladder pattern-matches on Failures and records the **actual** failure reason into fallback provenance (fixes the lying `reasoning:` string).
- `rescue Exception`: banned (RuboCop `Lint/RescueException` enforced in CI).
- Out-of-range LLM numerics → `Failure(:out_of_contract)` → retry once → fallback with provenance; no scale-guessing (F6 deleted).
- Extension/index setup failures are fatal at migration time, not warnings at runtime.

---

## 4. Performance Plan

Perf-skill discipline: nothing below is "optimized" until a profile names it and a committed benchmark shows ≥10-20%; the architecture changes in §3 are justified on correctness/design grounds, and this section defines how their performance claims get *measured*.

### 4.1 Measurement harness (built first — Phase 0)

- `bench/` in-repo, committed:
  - `bench/pipeline_bench.rb` — end-to-end `compile` on a production-shaped corpus (a real multi-section markdown doc + a 50-turn conversation fixture; toy inputs hide the real hotspots), `FakeAnnotator`/`FakeParser` variants to isolate stages from network noise.
  - `bench/store_bench.rb` — `replace_document` with 500 clauses, benchmark-ips, old per-clause loop vs `multi_insert`.
  - `bench/retrieval_bench.rb` — seeded pg with 50k clauses; filtered vs unfiltered retrieve.
- Profilers: `stackprof` (`mode: :wall` for the I/O-bound pipeline, `mode: :object` for allocation churn in aggregation/serialization), `memory_profiler` on `TenorTracker`/`Wire.dump` paths.
- SLIs recorded per run (the journald latency fields already emitted — `latency_ms` in pipeline/pass_one/pass_two — become the harness's assertions): **clauses/min end-to-end**, **LLM calls/document**, **DB statements/document**, **sidecar round-trips/section**, **peak RSS**.
- Every optimization lands as the YAML record the perf skill mandates (hotspot %, change, before/after ips, ratio, tests pass) or gets reverted.

### 4.2 Hypotheses, ranked by expected sample share (to be confirmed by profile, not assumed)

| # | Suspected hotspot | Evidence from code | Rebuild lever | How measured |
|---|---|---|---|---|
| H1 | Pass 2 LLM wall time dominates everything | In-code note: "one call per clause measured ~10 clauses/min" (`pass_two_engine.rb:23-25`); chunk timeout p50 ~35s (`:34`) | Keep batching (~12/call) + bounded concurrency; sidecar removal of the GVL hazard allows raising `SFL_CONCURRENCY` safely; cache hits skip calls entirely | wall-mode stackprof % in HTTP wait; LLM calls/document SLI; A/B concurrency 4→8 with error-rate guard |
| H2 | Per-job re-bootstrap in Gush path (F9) | `Bootstrap.call` + `Spacy::Language.new` per `CompileTurnJob#pipeline` (compile_turn_job.rb:88-93); spaCy import is "multi-second" (`cli.rb:571-577`) | Worker-boot-time wiring: connect DB + start sidecar once per worker process; jobs receive handles | time-per-job in Sidekiq logs before/after; expect O(seconds) per-job fixed cost → ~0 |
| H3 | Per-clause transactions & inserts (F7) | 3 inserts × N clauses × N transactions (pipeline.rb:94-98, clause_repository.rb:55-95) | `replace_document` multi_insert | `bench/store_bench.rb` ips ratio; DB statements/document SLI (expect 3N+N → ~4) |
| H4 | Sequential single-text embedding calls | `annotated.each { @embedder.embed(ac.text) }` (pipeline.rb:101-105) | batched `embed(texts)` against Ollama | wall time of embed stage on 500-clause doc |
| H5 | Deep `to_h`/re-validate churn (F5, D3) | TenorTracker rebuild per turn; CLI JSON self-round-trip; cache double-read (F10) | shallow `#new` updates; `Wire.load` once; `partition` returns hits | object-mode stackprof + memory_profiler allocation counts on a 200-turn result; expect major allocation drop, keep only if ≥10-20% on the aggregate stage |
| H6 | PyCall round-trips & token marshaling in Pass 1 | one `nlp.read` per section but per-token attribute access crosses the bridge (`extract_tokens_from_span`, pass_one_engine.rb:110-147) | sidecar returns fully-serialized token arrays in one message — one round-trip per section *including* attributes | sidecar round-trips/section SLI; wall-clock Pass 1 stage on the corpus before/after |
| H7 | Tokenizer object churn in MarkdownLoader | `PragmaticTokenizer::Tokenizer.new(OPTIONS)` **per paragraph** (markdown_loader.rb:205) | hoist to one instance per loader (idioms checklist: variable hoisting in hot loops) | benchmark-ips on `clean_text` over the corpus; likely small — revert if <10% |
| H8 | Retrieval post-filter (F8) | 3 extra queries + Ruby scan per retrieve (hybrid_retriever.rb:166-208) | SQL-side predicates | `bench/retrieval_bench.rb`; also *correctness* metric: recall under selective filters |

Explicit non-goals until profiled: micro-tuning string formatting in prompt rendering, yajl-vs-JSON (only revisit if `Wire` shows in an object profile), ivfflat index parameter tuning (needs real corpus statistics first).

---

## 5. Phased Rebuild Backlog

Phases are ordered so every phase ends green: characterization tests first, core outward, deletions continuous. Estimates assume one engineer familiar with the domain.

### Phase 0 — Safety net & triage (≈ 3-4 days)
- [ ] **Golden-master fixtures**: run current CLI on `spec/fixtures/conversations/sample.jsonl` + one markdown corpus with `FakeAnnotator`-style stubbed Pass 2; freeze CSV/JSON/MD outputs as characterization fixtures for the rebuild to diff against [1d]
- [ ] **Delete** `spec/integration/` (T1 — unloadable, API-rotten) and the stale template references; delete duplicate `spec/sfl/compiler/pass_two_engine_spec.rb` after merging any unique examples into the 482-line sibling (T2) [2h]
- [ ] Collapse `spec/sfl_compiler/**` into `spec/sfl/compiler/**` — one spec root (T2) [2h]
- [ ] Wire SimpleCov in `spec_helper.rb` with a recorded (not aspirational) baseline (T3) [1h]
- [ ] Stand up `bench/` harness + SLI recording (§4.1) and capture **current** numbers as the baseline the rebuild must beat [1d]
- [ ] Characterization spec for `PassOneEngine#process` with a stubbed spaCy double, including a repeated-token sentence — this test **fails today** and documents bug F1 as the sidecar's acceptance criterion (T4) [3h]

### Phase 1 — sfl-core: types, ports, sidecar Pass 1, Pass 2 engine (≈ 2-3 weeks)
- [ ] Scaffold `sfl-core` (gemsmith), pure Zeitwerk (one constant/file, no collapse/ignore/manifests — S2/S3), RuboCop config incl. `Lint/RescueException` [1d]
- [ ] Port `Types` → `SFL::Core::Types` + `Wire` serialization boundary with round-trip property tests (D3) [2d]
- [ ] Define ports (§3.3) + Null/Fake adapters + role tests (shared examples each adapter must pass — Metz role tests) [2d]
- [ ] **Python sidecar** (`SpacySidecarParser`): ~100-line Python NDJSON server (spaCy loaded once, positional head indices — fixes F1/D1); Ruby client with startup handshake, restart-on-crash, and the Phase-0 characterization spec now passing [4d]
- [ ] Port `IdeationalExtractor` (unchanged logic; verb lists become frozen constants/config) [1d]
- [ ] Rebuild `PassTwo::Engine`: split into `engine.rb`, `signatures/*`, `annotators/*`, `degradation.rb` (one file per constant — S3); structured inputs end-to-end (delete `parse_context` — I3); `Breaker` port with single timeout ownership; truthful fallback provenance; delete `clamp01` scale-guess in favor of contract rejection (F6, D9); config injected, zero ENV (S4) [4d]
- [ ] Rebuild `Pipeline`: no `GC.start` (D1 makes it obsolete), `replace_document` + batched embedding via ports, `Cache#partition` returns hits (F10), dry-monads Result ladder (§3.7) [2d]
- [ ] Port loaders (markdown/pdf/subtitle/exports/canvas/image) behind the `…Source` ducks with the owned `Unit` type (D4); hoist the PragmaticTokenizer instance (H7, measured) [3d]

### Phase 2 — sfl-store: schema, repositories, retrieval (≈ 1-1.5 weeks)
- [ ] Sequel versioned migrations replacing `Migrator`/`ColumnBackfill`; FKs + `ON DELETE CASCADE`; migration CLI task (never at boot/per-job) [2d]
- [ ] `PgClauseStore#replace_document` — single transaction, `multi_insert`, idempotency as repository contract (F7, D5); measured via `bench/store_bench.rb` [2d]
- [ ] Retrieval: filters pushed into both SQL arms, RRF in Ruby, recall test under selective filters (F8) [2d]
- [ ] Review-queue/annotation-review repositories ported as-is (their design — append-only audit trail, trusted-source predicate — is sound); `TRUSTED_ANNOTATION_SOURCES` stays the single predicate source [1d]
- [ ] `embedding_status` provenance + re-drive command for embedding gaps (F11) [1d]

### Phase 3 — Analysis unification (≈ 1.5 weeks)
- [ ] `Analysis::Engine` with the single compile loop + shared derivations; `ConversationSource`/`DocumentationSource`/`KnowledgeBaseSource` implement the duck (D2); golden-master diffs from Phase 0 must match (modulo the F4 fix, which is an intentional, documented output change) [4d]
- [ ] `Aggregations` as the only math implementation — engine, profiler, correlator, jobs; property tests pin defaults/rounding (F4) [1d]
- [ ] Immutable `TenorShifts.annotate` returning new arrays; shallow struct updates; position-independent shift lookup (F5) [1d]
- [ ] Chunk-artifact detection, KB scoring, narrative generation + citation grounding as composed post-processors [2d]
- [ ] Topic modeling pre-pass as an optional pipeline stage owned by the engine (not duplicated per analyzer) [1d]

### Phase 4 — Entry points (≈ 1 week)
- [ ] `sfl-cli`: `parse` (pure, tested) + thin `run_*` that only compose Boot + Engine + ReportWriter; the 4×-duplicated pipeline/embedder wiring (`cli.rb:250-257, 329-336, 382-389, 429-432`) becomes one factory; wiring specs with verified doubles (T4) [2d]
- [ ] `Boot` composition root: the **only** ENV reader, call-time only; explicit tracing setup replacing the Langfuse require-order ritual and both copies of the pre-flight dance (S4, D7); delete `yajl/json_gem` global patch (S6) [2d]
- [ ] Signal handling: sidecar removes the CPython-interrupt hazard, so `with_interrupts_deferred` is deleted; keep the two-stage Ctrl+C stop-flag (good UX, stays) [1d]
- [ ] Python provisioning: `sfl setup-python` command replacing `ext/` extconf entirely; delete `spec.extensions` (S5) [1d]

### Phase 5 — Optional surfaces: keep, extract, or delete (≈ 1 week for the "keep" set)
Explicit decisions, not drift:
- [ ] **sfl-jobs (keep, extracted):** Gush/Sidekiq fan-out is legitimate for large corpora even post-sidecar (multi-core). Worker boots once (DB + sidecar + LM), jobs call `Engine#compile_unit` (F9, F4); `-c 1` requirement disappears with PyCall (D1) [3d]
- [ ] **sfl-api (fix-or-drop decision gate):** if kept — async path uses the owned `Turn` constructor (fixes F2 mechanically), tmp-file cleanup, CORS/config injected; if no consumer exists, delete and keep `config.ru` out of the core [2d or 0]
- [ ] **sfl-tui (keep, thin):** post-sidecar the TUI can host analysis in-process; `WorkflowPoller` remains only for the jobs gem [2d]
- [ ] **Delete to `experiments/`:** `question_graph`, `cognitive_gas` (or keep solely as a `Breaker` adapter if the budget idea is still wanted), `convergence_detector`, `derivation_hash` + reasoning-trace hashing, GEB sprint jobs/workflow + `--sprint-id` flag, `narrative_self_analyzer`, `chat/`, `review_gui/` (glimmer), `theme_rheme_extractor`, `langfuse_reachability` (obsoleted by Phase 4), `api_boot`/`canvas_loader` if unowned (D8) [1d]
- [ ] **Delete outright:** `SafeOpenAIClientProxy`/`SafeChatProxy`/`SafeCompletionsProxy` chain + `apply_request_timeout`/`apply_generation_params` reflection (superseded by adapter config or upstream PR — I1); hand-built `define_singleton_method` breaker (I2); `scripts/parse_metacognitive_coprocessor.rb` hardcoded-path script (replaced by the CLI) [—]

### Phase 6 — Hardening (≈ 3-4 days)
- [ ] PBO pass over §4 hypotheses with the bench harness; keep ≥10-20% wins, revert the rest, commit the YAML records [2d]
- [ ] Coverage gate at the Phase-0 baseline + 10 points; CI runs specs, RuboCop, bench smoke [1d]
- [ ] YARD on all public API (ports, engine, stores, CLI) — public = commitment; everything else `private` by default (orchestrator Mandate 5) [1d]

**Total: ≈ 7-9 weeks.** The end state: a consumer can `gem install sfl-core sfl-store sfl-llm sfl-cli`, run `sfl setup-python` once, and analyze a corpus — with no TUI/GUI/server/queue dependencies, no require-order rituals, no GC-timing correctness, one analyzer engine, one turn schema, one `mean`, and a Pass 1 whose dependency graph is actually right.
