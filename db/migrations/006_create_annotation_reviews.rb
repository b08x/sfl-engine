# frozen_string_literal: true

# Append-only audit trail for human review decisions on a clause's Pass 2
# annotation (SFL::Core::Types::AnnotationReview) — the "is this
# already-stored, already-trusted-as-text mood/tenor/etc annotation correct"
# review flow, distinct from review_queue (007), which is about whether the
# underlying TEXT itself is trustworthy before it's ever stored.
#
# Deliberately no FK to clauses.external_id — same plain-string-key
# convention legacy settled on for this table (see
# sfl-compiler/lib/sfl/compiler/storage/database.rb's
# create_annotation_reviews_table comment) and the exception this slice's
# card explicitly calls out as sound as-is: this is an append-only audit
# log, not a payload row scoped 1:1 to a clause, so ON DELETE CASCADE would
# be wrong even if a real FK were added — deleting a clause should not
# silently erase the historical record that a human once reviewed it.
Sequel.migration do
  change do
    create_table(:annotation_reviews) do
      String :id, primary_key: true # UUID
      String :clause_id, null: false
      String :decision, null: false
      String :original_annotation_source, null: false
      String :reviewer
      String :notes, text: true
      DateTime :reviewed_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :clause_id, name: :idx_annotation_reviews_clause_id
    end
  end
end
