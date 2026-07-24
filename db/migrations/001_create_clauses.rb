# frozen_string_literal: true

# Base clause table: one row per SFL::Core::Types::AnnotatedClause, keyed on
# `external_id` (the AnnotatedClause's own `id`, a fresh UUID per compile —
# NOT SyntacticClause#id, which is a separate uuid Pass 1 assigns and which
# this schema does not preserve; see PgClauseStore for the same collapse
# legacy's ClauseRepository already made when reconstructing).
#
# `tokens`/`groups` snapshot the full SyntacticClause#tokens/#groups arrays
# as jsonb so PgClauseStore#find_by_document can rebuild SyntacticToken/
# SyntacticGroup structs without a fresh Pass 1 parse. `root_index` is
# stored directly as an Integer rather than legacy's `root_token` jsonb
# snapshot + "first token whose dep is ROOT" recompute on read — that
# recompute silently defaults to 0 when no token has dep "ROOT" (e.g. an
# empty tokens array), which storing the index verbatim avoids.
Sequel.migration do
  change do
    create_table(:clauses) do
      primary_key :id
      String :external_id, null: false
      String :text, null: false, text: true
      String :document_id
      Integer :sentence_index, null: false
      Integer :root_index, null: false
      column :tokens, :jsonb, default: "[]"
      column :groups, :jsonb, default: "[]"
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :external_id, unique: true
      index :document_id
      index Sequel.function(:to_tsvector, "simple", :text),
        type: :gin, name: :idx_clauses_tsv
    end
  end
end
