# lib/sfl/gui/text_review_control.rb
# frozen_string_literal: true

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
          # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          visible <= [viewmodel, :detail_kind, on_read: ->(kind) { kind == :text }]
          # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

          multiline_entry {
            text <=> [viewmodel, :edited_text]
          }

          # rubocop:disable Style/StringLiterals
          button('Save & Recompile') {
            # rubocop:enable Style/StringLiterals
            on_clicked do
              result = viewmodel.save_and_recompile!
              # rubocop:disable Style/StringLiterals
              msg_box_error('Recompile failed', result.failure.inspect) if result.failure?
              # rubocop:enable Style/StringLiterals
            end
          }
        }
      }
    end
  end
end
