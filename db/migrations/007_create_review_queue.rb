# frozen_string_literal: true

# Content-review queue — separate from annotation_reviews (006), which
# tracks Pass 2 confidence decisions on text everyone already trusts. This
# table tracks whether the underlying text ITSELF (a vision model's
# description of an image, a low-quality/fallback text extraction, a
# transcript segment) is correct before it's ever permanently stored.
#
# No FK, same plain-string-key convention as annotation_reviews — pre-trust
# content, sound as-is per this slice's card.
Sequel.migration do
  change do
    create_table(:review_queue) do
      String :id, primary_key: true # UUID
      String :modality, null: false # "image" | "text" | "audio"
      String :document_id, null: false
      String :source_file, text: true
      String :content_type
      String :source_type
      String :generated_text, text: true, null: false
      String :reason, null: false
      String :status, null: false, default: "pending"
      String :reviewer
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :reviewed_at

      index :status, name: :idx_review_queue_status
      index :document_id, name: :idx_review_queue_document_id
    end
  end
end
