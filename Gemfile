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
gem "zeitwerk", "~> 2.6"

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
gem "dspy", "~> 1.0"
gem "dspy-anthropic", "~> 1.0"
gem "dspy-o11y", "~> 1.0"
gem "dspy-o11y-langfuse", "~> 1.0"
gem "dspy-openai", "~> 1.0"

# Alternative/Extended LLM tooling
gem "nexo_ai", "~> 0.11.0"
gem "ruby_llm-docker", "~> 0.3.0"
gem "ruby_llm-mcp", "~> 1.0"
gem "ruby_llm-template", "~> 0.1.6"

# =============================================================================
# OBSERVABILITY & TRACING
# =============================================================================
# Tracing continuity to Langfuse via OTel (track decision 7), replacing dspy-o11y-langfuse

gem "opentelemetry-exporter-otlp", "~> 0.34"
gem "opentelemetry-sdk", "~> 1.12"

# Logging
gem "journald-logger", "~> 3.1"

# =============================================================================
# SOURCE LOADERS (Phase 1)
# =============================================================================
# markdown/pdf/subtitle/canvas/image/export/csv/json Source ducks

# Standard library replacements (no longer default gems)
gem "csv", "~> 3.3" # no longer a default gem as of Ruby 3.4, for CsvSource

# Markdown processing
gem "inkmark", "~> 0.1" # markdown -> HTML AST, for MarkdownSource
gem "pragmatic_tokenizer", "~> 3.2" # prose normalisation, for MarkdownSource

# JSON processing
gem "yajl-ruby", "~> 1.4", require: "yajl" # JSON/JSONL parsing, for the export/JSON Sources

# Obsidian Canvas
gem "json_canvas", "~> 0.1" # Obsidian .canvas node-graph parsing, for CanvasSource

# PDF processing
gem "kreuzberg", "~> 4.10" # PDF text + sentence-aware chunking, for PdfSource

# =============================================================================
# TOPIC MODELING & ANALYSIS (Phase 3)
# =============================================================================
# lib/sfl/analysis: topic modeling pre-pass, shared by every Analysis::Source.
# Legacy's gemspec pinned "~> 0.3"; only 0.6.2 is available in this sandbox and its
# Ruby-level LDA/HDP API (documented kwargs, #add_doc/#make_doc/#infer/#train/
# #topic_words/#burn_in=) matches what legacy's TopicModeler calls, verified by
# reading the installed gem's source directly (lib/tomoto/{lda,hdp}.rb).

gem "tomoto", "~> 0.6"

# Language detection
gem "lingua", "~> 0.6.2"

# =============================================================================
# RETRIEVAL & SEARCH ALGORITHMS
# =============================================================================

# Vector search algorithms
gem "bm25f", "~> 0.2.6"
gem "tf-idf-similarity", "~> 0.3.0"

# Schema validation
gem "schematist", "~> 1.1"

# =============================================================================
# STORAGE (Phase 2)
# =============================================================================
# Postgres-backed ClauseStore/EmbeddingStore adapters.
# Versions match what legacy sfl-compiler pins/locks (pg 1.6.3, pgvector 0.3.3,
# sequel 5.106.0 already installed locally) — verified compatible with this
# toolchain rather than assumed from memory (Context7 + local gem source read
# for both sequel's foreign_key key: option and pgvector-ruby's Pgvector.encode).

# Database drivers
gem "pg", "~> 1.5"
gem "pgvector", "~> 0.3"
gem "sequel", "~> 5.88"

# =============================================================================
# HTTP API (Phase 5)
# =============================================================================
# HTTP surface over the pipeline/retrieval/review-queue collaborators (lib/sfl/api).
# falcon is the Rack server config.ru/ exe/sfl-api run under (matches legacy's choice).

# Rack-based server
gem "falcon", "~> 0.47"
gem "rack", "~> 3.1"

# Alternative web framework
gem "roda", "~> 3.107"

# =============================================================================
# CLI UX
# =============================================================================
# A real progress bar (turn/artifact completion + ETA) replacing the old plain
# print/puts pair, and an interactive setup wizard (bin/setup-config) for .env
# — both from the TTY toolkit (ruby-dev skill's TUI Builder gem set).

# TTY toolkit
gem "tty-progressbar", "~> 0.18"
gem "tty-prompt", "~> 0.23"

# Alternative progress bar
gem "informers", "~> 1.3"

# =============================================================================
# GUI (Phase 6)
# =============================================================================
# lib/sfl/gui, exe/sfl-review: first desktop app, wraps Store::PgReviewQueueRepository.
# Bundles libui (the `libui` gem) — no Java/Electron dependency, prerequisite-free
# native windows.

# Native GUI framework
gem "glimmer-dsl-libui", "~> 0.13"

# fiddle dropped out of Ruby's default gems as of 4.0 (this app's pinned Ruby);
# the `libui` gem's FFI layer requires "fiddle/import" unconditionally, so it must
# be declared explicitly here or `require "glimmer-dsl-libui"` raises LoadError
# under `bundle exec` (discovered running this task's spike).
gem "fiddle", "~> 1.1"

# =============================================================================
# TUI (Phase 7)
# =============================================================================
# lib/sfl/tui, exe/sfl-tui: the keyboard-driven console over the
# pipeline/retrieval/review-queue collaborators, per docs/tui-implementation-plan.md §1.
# These are the charm-ruby ports (marcoroth/*-ruby) of Charm's Go libraries:
# pre-1.0, single-maintainer, with no semver guarantee yet, so each constraint is
# narrowed to the minor series this toolchain is installed and verified against
# ("~> 0.1.4" admits 0.1.x, not 0.2.0) rather than a loose "~> 0.1" — a 0.2.x bump here
# is a breaking-change risk, not a patch. The constraint is a floor on blast radius,
# NOT the determinism mechanism: the committed Gemfile.lock plus its sha256 CHECKSUMS
# block is what actually pins the exact versions every run resolves to. Verified
# loading clean under Ruby 4.0.4 with the prebuilt native extensions (Phase 0 spike).
# lipgloss/glamour ship prebuilt .so; bubbles is pure Ruby.

# Elm-style MVU runtime
gem "bubbletea", "~> 0.1.4" # Elm-style MVU runtime (Runner, Model, Message)

# UI component libraries
gem "bubbles", "~> 0.1.1" # List/Viewport/TextInput/Spinner sub-models
gem "glamour", "~> 0.2.2" # markdown -> ANSI for the synthesis/detail panes
gem "lipgloss", "~> 0.2.2" # pane styling + join_horizontal/join_vertical layout

# Alternative TUI framework
gem "ratatui_ruby", "~> 1.5"

# =============================================================================
# MEDIA PROCESSING
# =============================================================================

gem "image_processing", "~> 2.1"

# =============================================================================
# UTILITIES
# =============================================================================

# General-purpose algorithms
gem "algorithms", "~> 1.1"

# CLI tool for running external commands
gem "terrapin", "~> 1.1"

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
end

# =============================================================================
# PERFORMANCE PROFILING
# =============================================================================

group :perf do
  gem "benchmark-ips"
  gem "memory_profiler"
  gem "stackprof"
end
