# frozen_string_literal: true

# One row per run (an ingest, an annotation, an export or a recompile), keyed
# by the process's SFL_RUN_ID. CLI::PgRunProgressSink writes `done`,
# `current_item` and `heartbeat_at` as the run advances. A running row whose
# heartbeat is old is shown as stalled, and one whose `pid` no longer exists
# as dead (Core::RunState). `collection` is the collection name, kept as text
# so a run row outlives a purged collection.
Sequel.migration do
  change do
    create_table(:runs) do
      String :run_id, primary_key: true
      String :kind, null: false
      String :collection
      String :status, null: false, default: "running"
      Integer :total, null: false, default: 0
      Integer :done, null: false, default: 0
      Integer :failed, null: false, default: 0
      String :current_item, text: true
      Integer :pid
      DateTime :started_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :heartbeat_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :finished_at

      index :started_at
      index :status
    end
  end
end
