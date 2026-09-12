# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One edge in the graph-relational view of stored clauses (GET
      # /graph/edges) — either a structural parent/child chunk link or a
      # semantic-similarity link derived from embeddings.
      class GraphEdge < Dry::Struct
        attribute :from_id, Types::String
        attribute :to_id, Types::String
        attribute :edge_type, Types::String.enum("parent_child", "semantic_similarity")
        attribute :weight, Types::Float.optional.default(nil)
      end
    end
  end
end
