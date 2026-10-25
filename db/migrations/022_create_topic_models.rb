# frozen_string_literal: true

# One row per topic-model fit of a document. A document may be fitted more than
# once, so the table is not unique on (collection_key, document_key): every fit
# is kept as an audit trail and the store reads the highest id as the latest.
#
# topics:      JSON array of integers, one per turn in order; -1 marks an outlier.
# topic_words: JSON object mapping topic id strings to arrays of strings.
# run_id:      SFL_RUN_ID of the run that produced the fit; null when unset.
Sequel.migration do
  change do
    create_table(:topic_models) do
      primary_key :id, type: :bigserial
      String :collection_key, null: false
      String :document_key, null: false
      jsonb :topics, null: false
      jsonb :topic_words, null: false
      Float :coverage, null: false
      Integer :attempts, null: false
      String :run_id, null: true
      column :created_at, "timestamptz", null: false, default: Sequel::CURRENT_TIMESTAMP

      index %i[collection_key document_key created_at]
    end
  end
end
