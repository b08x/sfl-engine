# frozen_string_literal: true

require "sequel"
require "pgvector"

module SFL
  module Store
    # Postgres-backed hybrid retriever: semantic (pgvector cosine) + keyword
    # (Postgres full-text) search, merged with Reciprocal Rank Fusion.
    #
    # F8 fix vs legacy's HybridRetriever: legacy ran both search arms
    # UNFILTERED at `limit * 3`, RRF-merged, THEN filtered the merged set,
    # THEN took `.first(limit)` — so a selective filter (e.g. mood:
    # "imperative" against a mostly-declarative corpus) could starve the
    # final result to fewer than `limit` rows even when more matching rows
    # existed deeper in the corpus that were never fetched. Here,
    # ClauseFilters.apply pushes every RetrievalFilters attribute into the
    # SQL `.where(...)` of BOTH arms BEFORE their `.order`/`.limit`, so the
    # `limit * 3` candidate pool per arm is already filter-matching. RRF
    # merge itself stays in Ruby — a small in-memory merge over at most
    # `2 * (limit * 3)` rows, no need to push that into SQL too.
    class PgHybridRetriever
      include Core::Ports::Retriever

      RRF_K = 60 # Standard RRF constant, same as legacy.
      CANDIDATE_MULTIPLIER = 3

      # @param db [Sequel::Database]
      # @param embedder [Core::Ports::Embedder] injected, not a global/singleton
      #   (this app's DI convention) — unlike legacy's optional `embedder: nil`
      #   kwarg, v2's embedder is always present; "no embedding available" is
      #   detected from #embed's return value (an empty Array, matching
      #   Null::Embedder), not from embedder truthiness.
      def initialize(db:, embedder:)
        @db = db
        @embedder = embedder
      end

      # @param query [Core::Types::RetrievalQuery]
      # @return [Array<Core::Types::RetrievalResult>] sorted by rrf_score
      #   descending, at most query.limit rows
      def retrieve(query)
        candidate_limit = query.limit * CANDIDATE_MULTIPLIER

        semantic_rows = semantic_search(query.query, candidate_limit, query.filters)
        keyword_rows = keyword_search(query.query, candidate_limit, query.filters)

        reciprocal_rank_fusion(semantic_rows, keyword_rows)
          .first(query.limit)
          .map { |row| build_result(row) }
      end

      # Empty vector (Null::Embedder's behavior, and the real Embedder
      # port's contract for "nothing to embed") skips the semantic arm
      # gracefully rather than sending a malformed `<=>` comparison to
      # Postgres — the same defensive posture as legacy's guard, just keyed
      # off the vector itself instead of an optional embedder.
      private def semantic_search(query_text, limit, filters)
        vector_values = @embedder.embed(query_text)
        return [] if vector_values.empty?

        vector = Pgvector.encode(vector_values)

        scope = ClauseFilters.apply(joined_from_embeddings, filters)

        scope
          .order(Sequel.lit("embedding <=> ?", vector))
          .limit(limit)
          .select(*result_columns)
          .to_a.each_with_index.map { |row, idx| row.merge(semantic_rank: idx + 1) }
      end

      private def keyword_search(query_text, limit, filters)
        scope = ClauseFilters.apply(joined_from_clauses, filters)
          .where(Sequel.lit("to_tsvector('simple', clauses.text) @@ plainto_tsquery('simple', ?)", query_text))

        scope
          .order(Sequel.lit("ts_rank(to_tsvector('simple', clauses.text), plainto_tsquery('simple', ?)) DESC",
            query_text))
          .limit(limit)
          .select(*result_columns)
          .to_a.each_with_index.map { |row, idx| row.merge(keyword_rank: idx + 1) }
      end

      private def joined_from_embeddings
        @db[:embeddings]
          .join(:clauses, external_id: :clause_id)
          .join(:interpersonal_payloads, clause_id: Sequel[:clauses][:external_id])
          .join(:ideational_payloads, clause_id: Sequel[:clauses][:external_id])
      end

      private def joined_from_clauses
        @db[:clauses]
          .join(:interpersonal_payloads, clause_id: Sequel[:clauses][:external_id])
          .join(:ideational_payloads, clause_id: Sequel[:clauses][:external_id])
      end

      # Same columns for both arms, so RRF merge sees identically-shaped
      # rows regardless of which arm(s) a clause_id came from. mood/tenor/
      # process_type ride along for free here because both arms already
      # join interpersonal_payloads/ideational_payloads to apply filters
      # (see RetrievalResult's field-inlining decision).
      private def result_columns
        [
          Sequel[:clauses][:external_id].as(:clause_id),
          Sequel[:clauses][:text],
          Sequel[:clauses][:document_id],
          Sequel[:interpersonal_payloads][:mood],
          Sequel[:interpersonal_payloads][:tenor],
          Sequel[:ideational_payloads][:process_type],
        ]
      end

      private def reciprocal_rank_fusion(semantic_rows, keyword_rows)
        scores = Hash.new { |h, k| h[k] = { rrf_score: 0.0, data: {} } }

        accumulate_rrf(scores, semantic_rows, :semantic_rank)
        accumulate_rrf(scores, keyword_rows, :keyword_rank)

        scores.map { |_, v| v[:data].merge(rrf_score: v[:rrf_score].round(6)) }
          .sort_by { |r| -r[:rrf_score] }
      end

      # One arm's rows folded into the running per-clause_id score/data
      # accumulator — shared by both the semantic and keyword arms so the
      # RRF formula (1 / (RRF_K + rank)) and the row-merge only exist once.
      private def accumulate_rrf(scores, rows, rank_key)
        rows.each do |row|
          entry = scores[row[:clause_id]]
          entry[:rrf_score] += 1.0 / (RRF_K + row.fetch(rank_key))
          entry[:data].merge!(row)
        end
      end

      # rubocop:disable Metrics/MethodLength -- one flat struct literal, one field per
      # RetrievalResult attribute; splitting it would only relocate, not reduce, this.
      private def build_result(row)
        Core::Types::RetrievalResult.new(
          clause_id: row[:clause_id],
          text: row[:text],
          document_id: row[:document_id],
          rrf_score: row[:rrf_score],
          semantic_rank: row[:semantic_rank],
          keyword_rank: row[:keyword_rank],
          mood: row[:mood],
          tenor: row[:tenor],
          process_type: row[:process_type]
        )
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
