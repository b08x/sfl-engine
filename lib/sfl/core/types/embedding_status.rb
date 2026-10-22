# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Provenance of a clause's embedding (F11): "pending" = never
      # attempted (the column's own DB default, see
      # db/migrations/008_add_embedding_status_to_clauses.rb), "embedded" =
      # a real vector was successfully written to `embeddings`, "failed" =
      # an embed attempt returned no usable vector for this clause (see
      # PgEmbeddingStore#replace_section and EmbeddingRedriver). Distinct
      # from "no embeddings row" — every clause always has a status, so
      # "needs (re-)embedding" is a normal query (`status IN ('pending',
      # 'failed')`) instead of an absence check.
      #
      # "not_applicable" = this clause is a parent chunk (another clause's
      # parent_clause_id points at it) — Pipeline#embed_all only embeds
      # leaves, so a parent can never move to "embedded" and must not sit
      # at "pending" forever (see PgClauseStore#clause_row, EmbeddingRedriver).
      EmbeddingStatus = String.default("pending").enum("pending", "embedded", "failed", "not_applicable")
    end
  end
end
