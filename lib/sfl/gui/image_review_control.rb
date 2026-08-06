# lib/sfl/gui/image_review_control.rb
# frozen_string_literal: true

module SFL
  module GUI
    # Renders the flagged image inline plus its editable generated
    # description, for a selected review_queue row whose modality is
    # "image". Always present in DetailPaneControl's tree; visible is
    # bound to viewmodel.detail_kind so it's provably the complement of
    # TextReviewControl's own visible binding (SIFT Finding 1 fix — see
    # ReviewQueueViewModel#detail_kind, the single source of truth both
    # controls read from).
    class ImageReviewControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          visible <= [viewmodel, :detail_kind, on_read: ->(kind) { kind == :image }]
          # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

          area {
            image(viewmodel.selected_item&.dig(:source_file), 400, 400)
          }

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
