# frozen_string_literal: true

# Archive state of a document. A document is archived when archived_at is not
# null. Archive sets it to the current time, unarchive sets it to null. Neither
# changes updated_at. Archived documents are kept by prune and excluded from
# default context retrieval.
Sequel.migration do
  change do
    add_column :documents, :archived_at, DateTime, null: true
  end
end
