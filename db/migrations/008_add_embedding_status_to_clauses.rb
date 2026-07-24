# frozen_string_literal: true

# F11 fix: before this column existed, a clause with no embeddings row
# looked identical to a clause where embedding was simply never requested
# (embed: false) — there was no port-level or DB-level record of which
# clauses successfully got a real vector vs which didn't, and no way to
# later ask "which clauses need to be (re-)embedded". `embedding_status`
# closes that gap; `embedding_error` carries the failure reason when
# status is "failed" (see PgEmbeddingStore#replace_document and
# EmbeddingRedriver).
#
# Every newly-inserted clause defaults to "pending" at the DB level — no
# change needed to PgClauseStore#clause_row, since a multi_insert row hash
# that omits the column still gets the column's own default applied by
# Postgres (verified live, see spec/store/pg_clause_store_spec.rb).
Sequel.migration do
  change do
    alter_table(:clauses) do
      add_column :embedding_status, String, null: false, default: "pending"
      add_column :embedding_error, String, text: true
      add_index :embedding_status
    end
  end
end
