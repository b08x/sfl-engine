# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # In-memory ClauseStore, keyed by document_id. Unlike Null, this one
        # actually remembers what it was given — for specs that need to
        # assert on write-then-read behavior without a real database.
        class ClauseStore
          include Ports::ClauseStore

          def initialize
            @documents = {}
          end

          def replace_document(document_id, clauses)
            @documents[document_id] = clauses.dup
            nil
          end

          def find_by_document(document_id)
            @documents.fetch(document_id, []).dup
          end
        end
      end
    end
  end
end
