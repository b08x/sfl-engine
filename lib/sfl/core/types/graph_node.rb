# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One node in the graph-relational view of stored clauses (GET
      # /graph/nodes) — maps to the frontend's ConvoGraph data model
      # (MessageNode/TrajectoryNode, in the separate
      # syncopated-context-compiler repo).
      class GraphNode < Dry::Struct
        attribute :id, Types::String
        attribute :parent_id, Types::String.optional.default(nil)
        attribute :document_id, Types::String.optional.default(nil)
        attribute :text, Types::String
        attribute :mood, Types::MoodType.optional.default(nil)
        attribute :tenor, Types::TenorValue.optional.default(nil)
        attribute :process_type, Types::ProcessType.optional.default(nil)
        attribute :node_type, Types::String.default("clause")
        attribute :readability, Readability.optional.default(nil)
      end
    end
  end
end
