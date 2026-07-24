# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory EmbeddingStore, keyed by document_id — for specs that
        # need to assert on what was actually written.
        class EmbeddingStore
          include Ports::EmbeddingStore

          def initialize
            @documents = {}
          end

          def replace_document(document_id, embeddings_by_clause_id)
            @documents[document_id] = embeddings_by_clause_id.dup
            nil
          end

          def find_by_document(document_id)
            @documents.fetch(document_id, {})
          end
        end
      end
    end
  end
end
