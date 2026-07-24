# frozen_string_literal: true

# Adds the provenance tag legacy's `clauses.source_type` column carried
# (e.g. "chat_native", "vault_markdown", "api") but which v2's 001 migration
# didn't yet need. This retrieval slice's `RetrievalFilters#source_type`
# filter (see lib/sfl/core/types/retrieval_filters.rb and
# lib/sfl/store/clause_filters.rb) is the first v2 consumer of it, so the
# column arrives here rather than speculatively in 001. Same default
# ("unspecified") and nullability legacy settled on after its own backfill.
Sequel.migration do
  change do
    alter_table(:clauses) do
      add_column :source_type, String, null: false, default: "unspecified"
      add_index :source_type
    end
  end
end
