# frozen_string_literal: true

source "https://rubygems.org"

# .ruby-version pins the production target (3.4.4, matching the legacy repo). No hard `ruby`
# pin here: this sandbox's interpreter (4.0.1) doesn't match it and there's no 3.4.4 installed
# via asdf/rbenv, so a Gemfile-level pin would block `bundle install` for local dev entirely.

# Core loading & typing (track decision 1: single app, no gemspec)
gem "amatch", "~> 0.4" # Jaro-Winkler fuzzy matching for ClassificationRegistry
gem "dotenv", "~> 3.2" # .env loading — read only by SFL::Boot (track decision 4), never at require time
gem "dry-monads", "~> 1.6"
gem "dry-struct", "~> 1.6"
gem "dry-types", "~> 1.7"
gem "zeitwerk", "~> 2.6"

# Pass 2 LLM annotation (track decision 7: replaces DSPy)
gem "ruby_llm", "~> 1.16"
gem "ruby_llm-schema", "~> 0.4"

# Tracing continuity to Langfuse via OTel (track decision 7), replacing dspy-o11y-langfuse
gem "opentelemetry-exporter-otlp", "~> 0.34"
gem "opentelemetry-instrumentation-ruby_llm", "~> 0.7"
gem "opentelemetry-sdk", "~> 1.12"

# Loaders (Phase 1 backlog item: markdown/pdf/subtitle/canvas/image/export/csv/json Source ducks)
gem "csv", "~> 3.3" # no longer a default gem as of Ruby 3.4, for CsvSource
gem "inkmark", "~> 0.1" # markdown -> HTML AST, for MarkdownSource
gem "json_canvas", "~> 0.1" # Obsidian .canvas node-graph parsing, for CanvasSource
gem "kreuzberg", "~> 4.10" # PDF text + sentence-aware chunking, for PdfSource
gem "pragmatic_tokenizer", "~> 3.2" # prose normalisation, for MarkdownSource
gem "yajl-ruby", "~> 1.4", require: "yajl" # JSON/JSONL parsing, for the export/JSON Sources

# Phase 3 analysis (lib/sfl/analysis): topic modeling pre-pass, shared by
# every Analysis::Source. Legacy's gemspec pinned "~> 0.3"; only 0.6.2 is
# available in this sandbox and its Ruby-level LDA/HDP API (documented
# kwargs, #add_doc/#make_doc/#infer/#train/#topic_words/#burn_in=) matches
# what legacy's TopicModeler calls, verified by reading the installed gem's
# source directly (lib/tomoto/{lda,hdp}.rb) rather than assumed from memory.
gem "tomoto", "~> 0.6"

# Phase 2 storage (lib/sfl/store): Postgres-backed ClauseStore/EmbeddingStore adapters.
# Versions match what legacy sfl-compiler pins/locks (pg 1.6.3, pgvector 0.3.3, sequel
# 5.106.0 already installed locally) — verified compatible with this toolchain rather
# than assumed from memory (Context7 + local gem source read for both sequel's
# foreign_key key: option and pgvector-ruby's Pgvector.encode).
gem "pg", "~> 1.5"
gem "pgvector", "~> 0.3"
gem "sequel", "~> 5.88"

# Phase 5 sfl-api: HTTP surface over the pipeline/retrieval/review-queue
# collaborators (lib/sfl/api). falcon is the Rack server config.ru/
# exe/sfl-api run under (matches legacy's choice).
gem "falcon", "~> 0.47"
gem "rack", "~> 3.1"

group :development, :test do
  gem "pry"
  gem "pry-byebug"
  gem "rack-test"
  gem "rake"
  gem "rspec"
  gem "rubocop"
  gem "rubocop-performance"
  gem "rubocop-rake"
  gem "rubocop-rspec"
  gem "rubocop-sequel"
  gem "rubocop-shopify"
  gem "rubocop-thread_safety"
  gem "ruby-lsp"
end

group :quality do
  gem "simplecov", require: false
end

group :perf do
  gem "benchmark-ips"
  gem "memory_profiler"
  gem "stackprof"
end
