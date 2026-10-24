# frozen_string_literal: true

source "https://rubygems.org"

# .ruby-version / .tool-versions pin 4.0.1 — the Ruby every gem in this Gemfile.lock is
# actually installed and verified against (issue #4: 3.4.4 was the aspirational legacy-repo
# target, but asdf ignores .ruby-version without opting into legacy_version_file, so every
# session had silently been running on 4.0.1 the whole time; 4.0.1 is now the documented one).

# =============================================================================
# CORE INFRASTRUCTURE
# =============================================================================
# Core loading, typing, and application foundation (track decision 1: single app, no gemspec)

# Autoloading and dependency management
gem "zeitwerk"

# Pin below 3.0: json 3.0 removed the `create_additions` keyword entirely
# (a deliberate security-hardening breaking change), but Sequel 5.108.0's
# Sequel.parse_json (lib/sequel/core.rb) still calls
# `JSON.parse(json, create_additions: false)` — harmless value, keyword
# just doesn't exist anymore in 3.x, so every jsonb-column read raises
# `ArgumentError: unknown keyword: create_additions`. Un-pin once Sequel
# ships a 3.x-compatible release.
#
# ruby_llm 2.1.x requires json < 4, so this pin is compatible with it.
# (ruby_llm 2.0.0 required json < 3 and conflicted with json 3.x.)
gem "json", "~> 2.21"
# Type system and data structures
gem "dry-monads", "~> 1.6"
gem "dry-struct", "~> 1.6"
gem "dry-types", "~> 1.7"
gem "sorbet-runtime"

# Configuration management
gem "dotenv", "~> 3.2" # .env loading — read only by SFL::Boot (track decision 4), never at require time

# Utility libraries
gem "amatch", "~> 0.4" # Jaro-Winkler fuzzy matching for ClassificationRegistry

# =============================================================================
# LLM ANNOTATION & DSPY PASS 2
# =============================================================================
# Pass 2 LLM annotation (track decision 7: reverted from ruby_llm to DSPy)

# DSPy core and provider integrations
gem "dspy"
gem "dspy-anthropic"
gem "dspy-o11y"
gem "dspy-o11y-langfuse"
gem "dspy-openai"

# Alternative/Extended LLM tooling
gem "ruby_llm-docker"
gem "ruby_llm-template"
# =============================================================================
# OBSERVABILITY & TRACING
# =============================================================================
# Langfuse tracing runs through dspy-o11y-langfuse (see lib/sfl/llm/tracing.rb:
# DSPy::Observability.configure!(adapter: :langfuse)). That gem exports through the
# OpenTelemetry SDK and OTLP exporter below; lib/ does not call OpenTelemetry directly.

gem "opentelemetry-exporter-otlp"
gem "opentelemetry-sdk"

# Logging
gem "journald-logger"

# =============================================================================
# SOURCE LOADERS (Phase 1)
# =============================================================================
# markdown/pdf/subtitle/canvas/image/export/csv/json Source ducks

# Standard library replacements (no longer default gems)
gem "csv", "~> 3.3" # no longer a default gem as of Ruby 3.4, for CsvSource

# Markdown processing
gem "inkmark" # markdown -> HTML AST, for MarkdownSource
gem "pragmatic_tokenizer" # prose normalisation, for MarkdownSource

# JSON processing
gem "yajl-ruby", require: "yajl" # JSON/JSONL parsing, for the export/JSON Sources

# Obsidian Canvas
gem "json_canvas" # Obsidian .canvas node-graph parsing, for CanvasSource

# PDF processing
gem "kreuzberg" # PDF text + sentence-aware chunking, for PdfSource

# =============================================================================
# TOPIC MODELING & ANALYSIS (Phase 3)
# =============================================================================
# lib/sfl/analysis: topic modeling pre-pass, shared by every Analysis::Source.
# Legacy's gemspec pinned "~> 0.3"; only 0.6.2 is available in this sandbox and its
# Ruby-level LDA/HDP API (documented kwargs, #add_doc/#make_doc/#infer/#train/
# #topic_words/#burn_in=) matches what legacy's TopicModeler calls, verified by
# reading the installed gem's source directly (lib/tomoto/{lda,hdp}.rb).

gem "tomoto"

# Language detection
gem "lingua"

# =============================================================================
# RETRIEVAL & SEARCH ALGORITHMS
# =============================================================================

# Vector search algorithms
gem "bm25f"
gem "tf-idf-similarity"

# Schema validation
gem "schematist"

# =============================================================================
# STORAGE (Phase 2)
# =============================================================================
# Postgres-backed ClauseStore/EmbeddingStore adapters.
# Versions match what legacy sfl-compiler pins/locks (pg 1.6.3, pgvector 0.3.3,
# sequel 5.106.0 already installed locally) — verified compatible with this
# toolchain rather than assumed from memory (Context7 + local gem source read
# for both sequel's foreign_key key: option and pgvector-ruby's Pgvector.encode).

# Database drivers
gem "pg"
gem "pgvector"
gem "sequel"

# =============================================================================
# HTTP API (Phase 5)
# =============================================================================
# HTTP surface over the pipeline/retrieval/review-queue collaborators (lib/sfl/api).
# falcon is the Rack server config.ru/ exe/sfl-api run under (matches legacy's choice).

# Rack-based server
gem "falcon"
gem "rack"

# Alternative web framework
gem "roda"

# =============================================================================
# CLI UX
# =============================================================================
# A real progress bar (turn/artifact completion + ETA) replacing the old plain
# print/puts pair, and an interactive setup wizard (bin/setup-config) for .env
# — both from the TTY toolkit (ruby-dev skill's TUI Builder gem set).

# TTY toolkit
gem "tty-progressbar"
gem "tty-prompt"
gem "tty-spinner"

# Alternative progress bar
gem "informers"

# =============================================================================
# TUI
# =============================================================================
# lib/sfl/tui, exe/sfl-tui: the keyboard-driven terminal UI (Browse, Search,
# Runs, Models tabs). ratatui_ruby wraps the Rust ratatui crate; the committed
# Gemfile.lock and its sha256 CHECKSUMS block pin the exact version.

gem "ratatui_ruby"

# =============================================================================
# MEDIA PROCESSING
# =============================================================================

gem "image_processing"

# =============================================================================
# UTILITIES
# =============================================================================

# General-purpose algorithms
gem "algorithms"

# CLI tool for running external commands
gem "terrapin"

# =============================================================================
# DEVELOPMENT & TEST DEPENDENCIES
# =============================================================================

group :development, :test do
  # Debugging
  gem "pry"
  gem "pry-byebug"

  # Testing
  gem "rack-test"
  gem "rake"
  gem "rspec"

  # Gherkin acceptance runner for features/*.feature (29 scenarios): the
  # implementer/verifier gates run `bundle exec cucumber`; before this pin the
  # gem was only installed globally, so the gates reported "not run: not in
  # the Gemfile bundle".
  gem "cucumber", "~> 12.0"

  # Code quality
  gem "rubocop"
  gem "rubocop-performance"
  gem "rubocop-rake"
  gem "rubocop-rspec"
  gem "rubocop-sequel"
  gem "rubocop-shopify"
  gem "rubocop-thread_safety"

  # Developer tools
  gem "ruby-lsp"
  gem "solargraph"
end

# =============================================================================
# QUALITY ASSURANCE
# =============================================================================

group :quality do
  gem "simplecov", require: false

  # Mutation-testing gate: the hardener runs `bundle exec mutant run --use rspec`;
  # before this pin the gem was only invocable through a temporary
  # BUNDLE_GEMFILE overlay in tmp/ because it was missing from the bundle.
  # mutant-rspec pins mutant itself exactly (= 0.17.0).
  gem "mutant-rspec", "~> 0.17.0", require: false

  # Gemfile.lock vulnerability scan (hardener gate): ran via the same tmp/
  # BUNDLE_GEMFILE overlay until now; `bundle exec bundler-audit check` should
  # work natively inside the bundle.
  gem "bundler-audit", "~> 0.9.3", require: false
end

# =============================================================================
# PERFORMANCE PROFILING
# =============================================================================

group :perf do
  gem "benchmark-ips"
  gem "memory_profiler"
  gem "stackprof"
end

gem "jsonl"

gem "pycall"
gem "ruby-spacy"

gem "tty-which"

gem "tty-command"

gem "tree_sitter_language_pack", "~> 1.20"

gem "rllama", "~> 1.2"

gem "bake", "~> 0.25.0", group: :development
gem "decode", "~> 0.30.0", group: :development
gem "rubydex", "~> 0.4.2", group: :development
