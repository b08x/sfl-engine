# frozen_string_literal: true

source "https://rubygems.org"

# .ruby-version pins the production target (3.4.4, matching the legacy repo). No hard `ruby`
# pin here: this sandbox's interpreter (4.0.1) doesn't match it and there's no 3.4.4 installed
# via asdf/rbenv, so a Gemfile-level pin would block `bundle install` for local dev entirely.

# Core loading & typing (track decision 1: single app, no gemspec)
gem "amatch", "~> 0.4" # Jaro-Winkler fuzzy matching for ClassificationRegistry
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
