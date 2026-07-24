# frozen_string_literal: true

# Interpersonal metafunction payload (Pass 2 annotation output), one row per
# clause. Same real-FK treatment as ideational_payloads (D5). `reasoning_trace`
# is defined directly here (jsonb, nullable) rather than as a legacy-style
# post-hoc ColumnBackfill add_column — there is no pre-existing v2 database
# to backfill, so the final shape goes straight into create_table.
Sequel.migration do
  change do
    create_table(:interpersonal_payloads) do
      primary_key :id
      foreign_key :clause_id, :clauses, type: String, null: false,
        key: :external_id, on_delete: :cascade
      String :mood, null: false
      Float :modality_weight, null: false, default: 0.5
      Float :tenor, null: false, default: 0.5
      String :speaker_attitude
      String :reasoning
      String :annotation_source, null: false, default: "llm"
      column :reasoning_trace, :jsonb
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :clause_id, unique: true
      index :modality_weight
      index :tenor
      index :mood
      # Composite index for the retrieval slice's scalar-filter + ranking
      # queries (mood + modality_weight + tenor together) — a plain Sequel
      # `index` call here (not a raw `run` SQL string as legacy used) keeps
      # this migration reversible like the rest of the `change` block.
      index %i[mood modality_weight tenor], name: :idx_interpersonal_scalar_filter
    end
  end
end
