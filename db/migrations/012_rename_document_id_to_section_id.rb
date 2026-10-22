# frozen_string_literal: true

# Renames the per-segment identifier on `clauses` and `review_queue` from
# `document_id` to `section_id`. The value is unchanged (for example
# "file#turn-3"): it always identified a section of a document, not the
# whole document. The indexes are renamed with their columns.
Sequel.migration do
  up do
    alter_table(:clauses) { rename_column :document_id, :section_id }
    run "ALTER INDEX clauses_document_id_index RENAME TO clauses_section_id_index"

    alter_table(:review_queue) { rename_column :document_id, :section_id }
    run "ALTER INDEX idx_review_queue_document_id RENAME TO idx_review_queue_section_id"
  end

  down do
    run "ALTER INDEX idx_review_queue_section_id RENAME TO idx_review_queue_document_id"
    alter_table(:review_queue) { rename_column :section_id, :document_id }

    run "ALTER INDEX clauses_section_id_index RENAME TO clauses_document_id_index"
    alter_table(:clauses) { rename_column :section_id, :document_id }
  end
end
