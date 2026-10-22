# frozen_string_literal: true

# A collection is a named group of documents (a folder of papers, a set of
# transcripts). Names keep their case but are unique ignoring case, so the
# unique index is on lower(name). Store::PgCollectionRepository trims names
# and rejects empty ones before they reach this table; the CHECK is the
# database-side guard for the same rule.
Sequel.migration do
  change do
    create_table(:collections) do
      primary_key :id
      String :name, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index Sequel.function(:lower, :name), unique: true, name: :idx_collections_lower_name
      constraint(:chk_collections_name_present) { Sequel.lit("btrim(name) <> ''") }
    end
  end
end
