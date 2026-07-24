# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop]

namespace :db do
  desc "Run pending Sequel migrations against DATABASE_URL (db/migrations)"
  task :migrate do
    require "sequel"
    Sequel.extension :migration
    require_relative "lib/sfl"

    db = SFL::Store::Database.connect
    SFL::Store::Database.setup_extensions(db)
    Sequel::Migrator.run(db, "db/migrations")
    db.disconnect
  end
end

namespace :embeddings do
  desc "Re-drive embeddings for every clause with embedding_status pending/failed (F11)"
  task :redrive do
    require_relative "lib/sfl"

    # No real (non-Null/Fake) Core::Ports::Embedder adapter exists in this
    # codebase yet — lib/sfl/llm/ only has Pass 2 annotation chat/prompt
    # code (Engine/ChatFactory/Config), no embedding adapter (confirmed via
    # grep before writing this task). Rather than invent one out of scope
    # for this slice, or silently no-op/fake success, this task fails
    # loudly and points at exactly where a real adapter belongs — the same
    # honesty this app's other Phase-4-deferred seams (see LLM::Config's
    # "Config value objects now, ENV-reading Boot later" pattern) already
    # commit to. Once a real Embedder adapter exists under lib/sfl/llm/,
    # this task's TODO becomes one line: build/inject it here instead of
    # raising.
    raise "SFL::Store::EmbeddingRedriver has no real Core::Ports::Embedder to run with yet — " \
      "lib/sfl/llm/ has no embedding adapter (only Pass 2 annotation chat/prompt code). " \
      "Add one under lib/sfl/llm/ (e.g. an Ollama/embeddinggemma adapter implementing " \
      "Core::Ports::Embedder#embed/#embed_batch) before wiring this task for real."

    # db = SFL::Store::Database.connect
    # embedder = SFL::LLM::???.new(...) # TODO: real Embedder adapter, once one exists
    # embedding_store = SFL::Store::PgEmbeddingStore.new(db)
    # summary = SFL::Store::EmbeddingRedriver.new(db:, embedder:, embedding_store:).call
    # puts "documents_processed=#{summary[:documents_processed]} " \
    #   "redriven=#{summary[:redriven]} still_failed=#{summary[:still_failed]}"
    # db.disconnect
  end
end
