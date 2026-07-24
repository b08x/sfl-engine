# frozen_string_literal: true

require "sequel"
require "time"

module SFL
  module Store
    # Postgres-backed ClauseStore. `#replace_document` is the pipeline's
    # single write entry point: one transaction deletes every existing
    # `clauses` row for the document and bulk-inserts the new set (F7 —
    # idempotency lives in the interface, not in caller discipline the way
    # legacy's separate `ClauseRepository#delete_by_document` method
    # required). Deleting only from `clauses` and trusting the
    # `ideational_payloads`/`interpersonal_payloads` `ON DELETE CASCADE`
    # foreign keys (db/migrations 002/003) to remove the payload rows is
    # deliberate — now that those FKs are real (D5), a manual multi-table
    # delete would just be duplicating what Postgres already guarantees.
    #
    # Note on id collapse (same as legacy's ClauseRepository): only
    # AnnotatedClause#id is persisted as the join key (`external_id` /
    # `clause_id`). SyntacticClause#id, IdeationalPayload#clause_id, and
    # InterpersonalPayload#clause_id are all distinct uuids upstream (see
    # Pipeline#build_annotated_clause), but #store never records them —
    # #find_by_document's reconstructed clauses have all three collapsed to
    # the outer AnnotatedClause#id. This is a pre-existing, accepted lossy
    # round trip (documented, not accidental).
    # rubocop:disable Metrics/ClassLength -- one storage adapter with one small,
    # single-purpose private method per struct type (clauses/ideational/interpersonal
    # row-building, then their mirror-image reconstruct_* readers); splitting further
    # would scatter one cohesive mapping across multiple files for no readability gain.
    class PgClauseStore
      include Core::Ports::ClauseStore

      # @param db [Sequel::Database]
      def initialize(db)
        @db = db
      end

      # @param document_id [String]
      # @param clauses [Array<Core::Types::AnnotatedClause>]
      # @return [void]
      def replace_document(document_id, clauses)
        @db.transaction do
          @db[:clauses].where(document_id:).delete
          insert_all(clauses)
        end
        nil
      end

      # @param document_id [String]
      # @return [Array<Core::Types::AnnotatedClause>]
      def find_by_document(document_id)
        rows = @db[:clauses]
          .where(document_id:)
          .order(:sentence_index, :id)
          .all

        rows.map { |row| reconstruct(row) }
      end

      private def insert_all(clauses)
        return if clauses.empty?

        @db[:clauses].multi_insert(clauses.map { |c| clause_row(c) })
        @db[:ideational_payloads].multi_insert(clauses.map { |c| ideational_row(c) })
        @db[:interpersonal_payloads].multi_insert(clauses.map { |c| interpersonal_row(c) })
      end

      private def clause_row(clause)
        {
          external_id: clause.id,
          text: clause.text,
          document_id: clause.document_id,
          sentence_index: clause.syntactic.sentence_index,
          root_index: clause.syntactic.root_index,
          tokens: Sequel.pg_jsonb(clause.syntactic.tokens.map(&:to_h)),
          groups: Sequel.pg_jsonb(clause.syntactic.groups.map(&:to_h)),
          created_at: clause.compiled_at,
        }
      end

      private def ideational_row(clause)
        ideational = clause.ideational
        {
          clause_id: clause.id,
          process_type: ideational.process_type,
          participants: Sequel.pg_jsonb(ideational.participants.map(&:to_h)),
          circumstances: Sequel.pg_jsonb(ideational.circumstances),
          raw_transitivity: Sequel.pg_jsonb(ideational.raw_transitivity),
          created_at: clause.compiled_at,
        }
      end

      # rubocop:disable Metrics/MethodLength -- one flat row-hash literal, one field per column
      private def interpersonal_row(clause)
        interpersonal = clause.interpersonal
        {
          clause_id: clause.id,
          mood: interpersonal.mood,
          modality_weight: interpersonal.modality_weight,
          tenor: interpersonal.tenor,
          speaker_attitude: interpersonal.speaker_attitude,
          reasoning: interpersonal.reasoning,
          annotation_source: interpersonal.annotation_source,
          reasoning_trace: reasoning_trace_jsonb(interpersonal.reasoning_trace),
          created_at: clause.compiled_at,
        }
      end
      # rubocop:enable Metrics/MethodLength

      # nil stays SQL NULL, not a stored JSON "null" — most annotation
      # sources (fallback/stub/human) carry no derivation to show.
      private def reasoning_trace_jsonb(reasoning_trace)
        return nil unless reasoning_trace

        Sequel.pg_jsonb(Core::Wire.dump(reasoning_trace))
      end

      # Jsonb payloads come back from Postgres with STRING keys, and as
      # Sequel::Postgres::JSONBArray/JSONBHash — Array/Hash-like, but not
      # `instance_of?(Array)`/`Hash`, which Dry::Types' strict Array()/
      # Hash() coercions require (same gotcha legacy's
      # ClauseRepository#find_pass_one_output documents; live-verified
      # against this DB before writing this, not assumed). Array()/#to_h
      # below convert to the plain types Dry::Struct needs.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat assembly of the four
      # already-factored reconstruct_* helpers below into the final AnnotatedClause; splitting
      # the two payload lookups into their own method would only relocate, not reduce, this.
      private def reconstruct(row)
        ideational = @db[:ideational_payloads].where(clause_id: row[:external_id]).first
        interpersonal = @db[:interpersonal_payloads].where(clause_id: row[:external_id]).first

        Core::Types::AnnotatedClause.new(
          id: row[:external_id],
          text: row[:text],
          syntactic: reconstruct_syntactic(row),
          ideational: reconstruct_ideational(ideational, row[:external_id]),
          interpersonal: reconstruct_interpersonal(interpersonal, row[:external_id]),
          document_id: row[:document_id],
          compiled_at: row[:created_at]
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def reconstruct_syntactic(row)
        Core::Types::SyntacticClause.new(
          id: row[:external_id],
          text: row[:text],
          tokens: Array(row[:tokens]).map { |t| reconstruct_token(t) },
          groups: Array(row[:groups]).map { |g| reconstruct_group(g) },
          root_index: row[:root_index],
          sentence_index: row[:sentence_index],
          document_id: row[:document_id]
        )
      end

      private def reconstruct_token(token_hash)
        Core::Types::SyntacticToken.new(
          text: token_hash["text"], lemma: token_hash["lemma"], pos: token_hash["pos"], tag: token_hash["tag"],
          dep: token_hash["dep"], head_index: token_hash["head_index"],
          morphology: (token_hash["morphology"] || {}).to_h, index: token_hash["index"]
        )
      end

      private def reconstruct_group(group_hash)
        Core::Types::SyntacticGroup.new(
          id: group_hash["id"], type: group_hash["type"], text: group_hash["text"],
          head_token_index: group_hash["head_token_index"],
          token_indices: Array(group_hash["token_indices"])
        )
      end

      private def reconstruct_ideational(row, clause_id)
        Core::Types::IdeationalPayload.new(
          clause_id:,
          process_type: row[:process_type],
          participants: Array(row[:participants]).map do |p|
            Core::Types::Participant.new(role: p["role"], text: p["text"])
          end,
          circumstances: Array(row[:circumstances]),
          raw_transitivity: (row[:raw_transitivity] || {}).to_h
        )
      end

      private def reconstruct_interpersonal(row, clause_id)
        Core::Types::InterpersonalPayload.new(
          clause_id:,
          mood: row[:mood],
          modality_weight: row[:modality_weight],
          tenor: row[:tenor],
          speaker_attitude: row[:speaker_attitude],
          reasoning: row[:reasoning],
          annotation_source: row[:annotation_source],
          reasoning_trace: reconstruct_reasoning_trace(row[:reasoning_trace])
        )
      end

      private def reconstruct_reasoning_trace(trace_hash)
        return nil unless trace_hash

        Core::Types::ReasoningTrace.new(
          premises: Array(trace_hash["premises"]).map { |p| reconstruct_premise(p) },
          inference_rule: trace_hash["inference_rule"],
          conclusion: (trace_hash["conclusion"] || {}).to_h,
          confidence: trace_hash["confidence"],
          derivation_hash: trace_hash["derivation_hash"],
          generated_at: Time.parse(trace_hash["generated_at"])
        )
      end

      private def reconstruct_premise(premise_hash)
        Core::Types::Premise.new(
          type: premise_hash["type"], source: premise_hash["source"],
          value: premise_hash["value"], weight: premise_hash["weight"]
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
