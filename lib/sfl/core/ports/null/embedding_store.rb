# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op EmbeddingStore: discards writes.
        class EmbeddingStore
          include Ports::EmbeddingStore

          def replace_document(_document_id, _embeddings_by_clause_id)
            nil
          end
        end
      end
    end
  end
end
