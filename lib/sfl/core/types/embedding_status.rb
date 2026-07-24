# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Provenance of a clause's embedding (F11): "pending" = never
      # attempted (the column's own DB default, see
      # db/migrations/008_add_embedding_status_to_clauses.rb), "embedded" =
      # a real vector was successfully written to `embeddings`, "failed" =
      # an embed attempt returned no usable vector for this clause (see
      # PgEmbeddingStore#replace_document and EmbeddingRedriver). Distinct
      # from "no embeddings row" — every clause always has a status, so
      # "needs (re-)embedding" is a normal query (`status IN ('pending',
      # 'failed')`) instead of an absence check.
      EmbeddingStatus = String.default("pending").enum("pending", "embedded", "failed")
    end
  end
end
