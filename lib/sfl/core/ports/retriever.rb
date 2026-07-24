# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Hybrid (semantic + keyword) ranked retrieval over stored clauses.
      # Deliberately a single small method: "flexible for agents/API" means
      # a stable, typed, well-documented contract, not more configuration
      # knobs — see the retrieval slice's card. A future agent-tool wrapper
      # or MCP server layer depends on this port's interface, not on
      # whether the backing implementation is Postgres, an in-memory fake,
      # or something else.
      module Retriever
        # @param query [SFL::Core::Types::RetrievalQuery]
        # @return [Array<SFL::Core::Types::RetrievalResult>]
        def retrieve(query)
          raise NotImplementedError, "#{self.class} must implement #retrieve"
        end
      end
    end
  end
end
