# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One ranked row out of Ports::Retriever#retrieve. A typed Dry::Struct
      # (not a raw Sequel Hash) — see RetrievalQuery/RetrievalFilters for the
      # same MCP/agent-tool-facing rationale. Round-trips cleanly through
      # Wire.dump (no Time-typed attributes here, so no Wire.load_retrieval_result
      # is needed — Dry::Struct's own Hash coercion is sufficient to rebuild one
      # from a parsed JSON hash).
      #
      # Decision: mood/tenor/process_type ARE inlined onto the result row.
      # PgHybridRetriever's semantic and keyword search arms already join
      # interpersonal_payloads/ideational_payloads to push RetrievalFilters
      # into SQL (the F8 fix — see PgHybridRetriever), so these three scalars
      # are sitting right there in the same joined row with no extra query.
      # An agent or API consumer gets useful metadata on every ranked hit
      # without a second lookup per clause_id. This stops short of a full
      # nested payload struct (participants, circumstances, reasoning_trace,
      # ...) — that's a step too far for a ranked list row and would mean
      # re-fetching/re-nesting data a search-result consumer usually doesn't
      # need until they open one specific clause.
      class RetrievalResult < Dry::Struct
        attribute :clause_id, Types::String
        attribute :text, Types::String
        attribute :document_id, Types::String.optional
        attribute :rrf_score, Types::Float
        attribute :semantic_rank, Types::Integer.optional.default(nil)
        attribute :keyword_rank, Types::Integer.optional.default(nil)
        attribute :mood, Types::MoodType.optional.default(nil)
        attribute :tenor, Types::TenorValue.optional.default(nil)
        attribute :process_type, Types::ProcessType.optional.default(nil)
        attribute :modality_weight, Types::ModalityWeight.optional.default(nil)
        attribute :annotation_source, Types::AnnotationSource.optional.default(nil)
        attribute :untrusted, Types::Bool.default(false)
      end
    end
  end
end
