# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Persists AnnotatedClauses. `replace_document` is the pipeline's
      # single write entry point (delete-then-insert under one document_id,
      # not per-clause upserts), so a re-run of the same document never
      # leaves stale clauses behind.
      module ClauseStore
        # @param document_id [String]
        # @param clauses [Array<SFL::Core::Types::AnnotatedClause>]
        # @return [void]
        def replace_document(document_id, clauses)
          raise NotImplementedError, "#{self.class} must implement #replace_document"
        end

        # @param document_id [String]
        # @return [Array<SFL::Core::Types::AnnotatedClause>]
        def find_by_document(document_id)
          raise NotImplementedError, "#{self.class} must implement #find_by_document"
        end
      end
    end
  end
end
