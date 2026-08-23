# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"
require "dotenv/load" if File.exist?(".env")

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

namespace :zeitwerk do
  desc "Check project structure for Zeitwerk compatibility"
  task :check do
    require "zeitwerk"
    require_relative "lib/sfl"

    begin
      SFL.loader.eager_load
      puts "Zeitwerk check passed."
    rescue NameError => e
      abort "Zeitwerk check failed: #{e.message}"
    end
  end
end

task default: %i[spec rubocop zeitwerk:check]

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

    # SFL::LLM::Embedder (Ollama-backed, Core::Ports::Embedder-compliant)
    # now exists — SFL::Boot resolves and injects it the same way it does
    # every other collaborator (track decision 4: ENV read only at Boot).
    # No migrations run here (SFL::Boot.connect_db deliberately never
    # migrates — see Store::Database's own comment); run `rake db:migrate`
    # first if this is a fresh database.
    ctx = SFL::Boot.call(require_tracing: false)
    embedding_store = SFL::Store::PgEmbeddingStore.new(ctx.db)
    summary = SFL::Store::EmbeddingRedriver.new(db: ctx.db, embedder: ctx.embedder, embedding_store:).call
    puts "documents_processed=#{summary[:documents_processed]} " \
      "redriven=#{summary[:redriven]} still_failed=#{summary[:still_failed]}"
    ctx.db.disconnect
  end
end
