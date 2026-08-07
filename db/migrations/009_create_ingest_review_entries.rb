# frozen_string_literal: true

# Ingest-time review queue: rows written when Ingest::Orchestrator can't
# confidently dispatch a file on its own (see Ingest::DeterministicRules /
# Core::Ports::Classifier / Ingest::LoaderDrafter). Mirrors review_queue's
# exact shape (db/migrations/007_create_review_queue.rb) — String UUID
# primary key, status defaults to "pending", indexed on status — so a
# future UI or CLI review subcommand is a pure read/query layer on this
# table, not a migration to write later.
Sequel.migration do
  change do
    create_table(:ingest_review_entries) do
      String :id, primary_key: true # UUID
      String :path, null: false, text: true
      # low_confidence_mode | loader_drafted | draft_failed | resolved
      String :status, null: false, default: "pending"
      String :format
      String :mode
      Float :confidence
      String :reasoning, text: true, null: false
      String :loader_path
      String :doc_path
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :resolved_at

      index :status, name: :idx_ingest_review_entries_status
    end
  end
end
