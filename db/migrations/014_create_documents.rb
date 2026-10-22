# frozen_string_literal: true

# A document is one whole item (a paper, a transcript, one chat
# conversation), identified by `document_key`. A chat export file holds many
# conversations, so `source_path` is not unique; `document_key` is.
# Deleting a collection deletes its documents.
Sequel.migration do
  change do
    create_table(:documents) do
      primary_key :id
      foreign_key :collection_id, :collections, null: false, on_delete: :cascade
      String :document_key, null: false, text: true
      String :source_path, text: true
      String :title, text: true
      String :source_type
      Integer :section_count, null: false, default: 0
      DateTime :ingested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :document_key, unique: true
      index :collection_id
    end
  end
end
