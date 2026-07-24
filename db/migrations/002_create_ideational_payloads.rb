# frozen_string_literal: true

# Ideational metafunction payload (Pass 1 transitivity output), one row per
# clause. `clause_id` is a real foreign key to clauses.external_id (D5 fix —
# legacy left this a plain String column with no constraint, relying
# entirely on ClauseRepository#delete_by_document's manual multi-table
# delete to keep rows in sync). `on_delete: :cascade` means deleting a
# clauses row alone is now enough to remove its payload rows.
Sequel.migration do
  change do
    create_table(:ideational_payloads) do
      primary_key :id
      foreign_key :clause_id, :clauses, type: String, null: false,
        key: :external_id, on_delete: :cascade
      String :process_type, null: false
      column :participants, :jsonb, default: "[]"
      column :circumstances, :jsonb, default: "[]"
      column :raw_transitivity, :jsonb, default: "{}"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :clause_id, unique: true
      index :process_type
    end
  end
end
