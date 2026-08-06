# lib/sfl/gui/text_review_control.rb
# frozen_string_literal: true

require_relative "failure_message"

module SFL
  module GUI
    # Same shape as ImageReviewControl minus the image — serves both
    # "text" and "audio" modalities identically (audio has no special
    # rendering need beyond its transcript text). visible is bound to
    # viewmodel.detail_kind, the same single source of truth
    # ImageReviewControl reads (SIFT Finding 1 fix).
    class TextReviewControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          # See ImageReviewControl for why computed_by is required here:
          # detail_kind has no writer, so without it Glimmer never observes it.
          # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          visible <= [viewmodel, :detail_kind, on_read: ->(k) { k == :text }, computed_by: [:selected_item]]
          # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

          multiline_entry {
            text <=> [viewmodel, :edited_text]
          }

          button("Save & Recompile") {
            on_clicked do
              result = viewmodel.save_and_recompile!
              msg_box_error("Recompile failed", FailureMessage.call(result.failure)) if result.failure?
            end
          }
        }
      }
    end
  end
end
