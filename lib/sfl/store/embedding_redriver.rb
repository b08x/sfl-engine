# frozen_string_literal: true

require "sequel"
require "pgvector"

module SFL
  module Store
    # F11 fix, part two: re-drives embeddings for every clause whose
    # `embedding_status` is "pending" (never embedded) or "failed" (a
    # previous embed attempt returned no usable vector — see
    # PgEmbeddingStore#replace_document). An operator-facing admin command
    # (`rake embeddings:redrive`, see Rakefile), not a pipeline stage — it
    # has no Core::Ports contract of its own, the same "no current second
    # backend to swap" reasoning as PgAnnotationReviewRepository/
    # PgReviewQueueRepository.
    #
    # Batches by document_id, not one clause at a time: embeddings are
    # written per-document via EmbeddingStore#replace_document, and the
    # Embedder port is itself batch-oriented (#embed_batch).
    #
    # Data-loss guard (the concern this class's own card calls out):
    # EmbeddingStore#replace_document deletes EVERY embeddings row for a
    # document before re-inserting (its own F7 idempotency contract) — so
    # re-driving only the gapped subset of a document and calling
    # #replace_document with just that subset would silently delete the
    # already-good vectors of every other, already-embedded clause in the
    # same document. #redrive_document avoids this by reading back the
    # current vectors for that document's non-gapped clauses first and
    # merging them with the freshly re-driven ones before calling
    # #replace_document — the full current embedding set for the document
    # goes in, not just the delta. A narrower "update these clause_ids
    # only" method on EmbeddingStore was considered and rejected: it would
    # duplicate #replace_document's delete-scope logic in a second place
    # for a benefit only this one admin command needs.
    class EmbeddingRedriver
      # @param db [Sequel::Database] read access to `clauses`/`embeddings`
      #   for finding gaps and reading back existing vectors to merge
      # @param embedder [Core::Ports::Embedder]
      # @param embedding_store [Core::Ports::EmbeddingStore]
      # @param model [String] must match the model EmbeddingStore writes
      #   under (PgEmbeddingStore::DEFAULT_MODEL by default) — needed here
      #   only to scope the "read back existing vectors" query correctly
      #   when more than one model's vectors coexist for the same clause;
      #   EmbeddingStore's own model choice stays private to that adapter.
      def initialize(db:, embedder:, embedding_store:, model: PgEmbeddingStore::DEFAULT_MODEL)
        @db = db
        @embedder = embedder
        @embedding_store = embedding_store
        @model = model
      end

      # @return [Hash] { documents_processed:, redriven:, still_failed: }
      def call
        results = gapped_document_ids.map { |document_id| redrive_document(document_id) }

        {
          documents_processed: results.size,
          redriven: results.sum { |r| r[:redriven] },
          still_failed: results.sum { |r| r[:still_failed] },
        }
      end

      private def gapped_document_ids
        @db[:clauses]
          .where(embedding_status: %w[pending failed])
          .exclude(document_id: nil)
          .distinct
          .select_map(:document_id)
      end

      private def redrive_document(document_id)
        gapped = gapped_clauses(document_id)
        return { redriven: 0, still_failed: 0 } if gapped.empty?

        new_by_clause_id = new_vectors_for(gapped)
        write_merged(document_id, gapped, new_by_clause_id)
        summarize(new_by_clause_id)
      end

      private def gapped_clauses(document_id)
        @db[:clauses]
          .where(document_id:, embedding_status: %w[pending failed])
          .select(:external_id, :text)
          .all
      end

      private def new_vectors_for(gapped)
        vectors = @embedder.embed_batch(gapped.map { |c| c[:text] })
        gapped.zip(vectors).to_h { |clause, vector| [clause[:external_id], vector] }
      end

      private def write_merged(document_id, gapped, new_by_clause_id)
        gapped_ids = gapped.map { |c| c[:external_id] }
        merged = existing_embeddings(document_id, gapped_ids).merge(new_by_clause_id)
        @embedding_store.replace_document(document_id, merged)
      end

      private def summarize(new_by_clause_id)
        redriven = new_by_clause_id.count { |_clause_id, vector| vector && !vector.empty? }
        { redriven:, still_failed: new_by_clause_id.size - redriven }
      end

      # Already-embedded clauses in this document that are NOT part of this
      # redrive batch — read back so the merge in #write_merged carries
      # them, unchanged, into #replace_document's payload (see class
      # comment's data-loss guard).
      private def existing_embeddings(document_id, gapped_clause_ids)
        rows_to_vectors(existing_embedding_rows(document_id, gapped_clause_ids))
      end

      private def existing_embedding_rows(document_id, gapped_clause_ids)
        @db[:embeddings]
          .join(:clauses, external_id: :clause_id)
          .where(Sequel[:clauses][:document_id] => document_id, Sequel[:embeddings][:model] => @model)
          .exclude(Sequel[:clauses][:external_id] => gapped_clause_ids)
          .select(Sequel[:embeddings][:clause_id], Sequel[:embeddings][:embedding])
          .all
      end

      private def rows_to_vectors(rows)
        rows.to_h { |row| [row[:clause_id], Pgvector.decode(row[:embedding])] }
      end
    end
  end
end
