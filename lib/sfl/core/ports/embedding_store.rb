# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Persists clause embeddings, kept separate from ClauseStore (its
      # own repository, mirroring the legacy split between
      # ClauseRepository and EmbeddingRepository) — vector storage is a
      # different backend/schema concern (pgvector) than clause text/
      # annotation storage, even though both are usually written together
      # at the end of one pipeline run.
      module EmbeddingStore
        # @param document_id [String]
        # @param embeddings_by_clause_id [Hash<String, Array<Float>>]
        # @return [void]
        def replace_document(document_id, embeddings_by_clause_id)
          raise NotImplementedError, "#{self.class} must implement #replace_document"
        end
      end
    end
  end
end
