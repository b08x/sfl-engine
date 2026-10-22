# frozen_string_literal: true

# A section is a segment of a document (a heading block, a paragraph block or
# a speaker's turn), identified by `section_id` — the same value
# `clauses.section_id` carries. Sections nest through `parent_section_id`,
# which references another section's `section_id`; deleting a parent leaves
# its children at the top level. Deleting a document deletes its sections.
Sequel.migration do
  change do
    create_table(:sections) do
      primary_key :id
      String :section_id, null: false, text: true, unique: true
      foreign_key :document_id, :documents, null: false, on_delete: :cascade
      String :parent_section_id, text: true
      Integer :ordinal, null: false
      String :kind, null: false
      String :label, text: true
      Integer :level
      Integer :clause_count, null: false, default: 0
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index %i[document_id ordinal]
      index :parent_section_id
      foreign_key [:parent_section_id], :sections, key: :section_id, on_delete: :set_null,
        name: :fk_sections_parent_section_id
    end
  end
end
