# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Input to Ports::Retriever#retrieve. A typed request struct (not a
      # raw Hash of query/limit/filters keys) so a future MCP tool
      # definition or JSON API request body has a real, introspectable
      # schema to validate against — see the retrieval slice's card for the
      # full rationale.
      class RetrievalQuery < Dry::Struct
        # Same rationale as RetrievalFilters: an MCP tool call or JSON API
        # body with a typo'd top-level key (e.g. "qeury") should raise, not
        # silently construct a query with the typo'd field ignored.
        schema schema.strict

        attribute :query, Types::String
        attribute :limit, Types::Integer.default(10)
        attribute(:filters, RetrievalFilters.default { RetrievalFilters.new })
      end
    end
  end
end
