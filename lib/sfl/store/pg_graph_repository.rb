# frozen_string_literal: true

require "sequel"
require "pgvector"

module SFL
  module Store
    # Read-only graph-relational view over `clauses`/`embeddings` for the
    # GET /graph/nodes and /graph/edges API endpoints — reuses the same
    # three-table join PgClauseStore/PgHybridRetriever already build,
    # rather than a parallel query path.
    class PgGraphRepository
      def initialize(db:, retriever: nil)
        @db = db
        @retriever = retriever
      end

      # @param document_id [String, nil] scope to one document, or all
      # @return [Array<Core::Types::GraphNode>]
      def nodes(document_id: nil)
        scope = joined_scope
        scope = scope.where(Sequel[:clauses][:document_id] => document_id) if document_id

        scope.select(
          Sequel[:clauses][:external_id].as(:id),
          Sequel[:clauses][:parent_clause_id].as(:parent_id),
          Sequel[:clauses][:document_id],
          Sequel[:clauses][:text],
          Sequel[:clauses][:readability_flesch],
          Sequel[:clauses][:readability_kincaid],
          Sequel[:clauses][:readability_fog],
          Sequel[:clauses][:word_count],
          Sequel[:interpersonal_payloads][:mood],
          Sequel[:interpersonal_payloads][:tenor],
          Sequel[:ideational_payloads][:process_type]
        ).all.map { |row| build_node(row) }
      end

      # @param document_id [String, nil] scope to one document, or all
      # @return [Array<Core::Types::GraphEdge>]
      def parent_child_edges(document_id: nil)
        scope = @db[:clauses].exclude(parent_clause_id: nil)
        scope = scope.where(document_id:) if document_id

        scope.select(:external_id, :parent_clause_id).all.map do |row|
          Core::Types::GraphEdge.new(from_id: row[:parent_clause_id], to_id: row[:external_id],
            edge_type: "parent_child")
        end
      end

      # Semantic-similarity neighbors of one clause's own embedding vector
      # — reuses PgHybridRetriever's pgvector cosine-distance pattern,
      # scoped to a single seed clause rather than a text query.
      #
      # @param clause_id [String] AnnotatedClause#id
      # @param k [Integer] max neighbors to return
      # @param min_similarity [Float] 1 - cosine_distance floor
      # @return [Array<Core::Types::GraphEdge>]
      def semantic_neighbors(clause_id, k: 5, min_similarity: 0.75)
        seed = @db[:embeddings].where(clause_id:).first
        return [] unless seed

        @db[:embeddings]
          .exclude(clause_id:)
          .select(:clause_id, Sequel.lit("1 - (embedding <=> ?) AS similarity", seed[:embedding]))
          .having { Sequel.lit("1 - (embedding <=> ?)", seed[:embedding]) >= min_similarity }
          .order(Sequel.lit("embedding <=> ?", seed[:embedding]))
          .limit(k)
          .all
          .map do |row|
            Core::Types::GraphEdge.new(from_id: clause_id, to_id: row[:clause_id],
              edge_type: "semantic_similarity", weight: row[:similarity])
          end
      end

      private def joined_scope
        @db[:clauses]
          .join(:interpersonal_payloads, clause_id: Sequel[:clauses][:external_id])
          .join(:ideational_payloads, clause_id: Sequel[:clauses][:external_id])
      end

      private def build_node(row)
        Core::Types::GraphNode.new(
          id: row[:id],
          parent_id: row[:parent_id],
          document_id: row[:document_id],
          text: row[:text],
          mood: row[:mood],
          tenor: row[:tenor],
          process_type: row[:process_type],
          readability: build_readability(row)
        )
      end

      private def build_readability(row)
        return nil if row[:readability_flesch].nil? && row[:readability_kincaid].nil? &&
          row[:readability_fog].nil? && row[:word_count].nil?

        Core::Types::Readability.new(
          flesch: row[:readability_flesch], kincaid: row[:readability_kincaid],
          fog: row[:readability_fog], word_count: row[:word_count]
        )
      end
    end
  end
end
