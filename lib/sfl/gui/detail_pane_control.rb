# lib/sfl/gui/detail_pane_control.rb
# frozen_string_literal: true

require_relative "image_review_control"
require_relative "text_review_control"

module SFL
  module GUI
    # Right pane: selected-row metadata, the modality-specific review
    # control (exactly one of ImageReviewControl/TextReviewControl is
    # visible at a time, or neither if nothing recognized is selected —
    # see the fallback label below), and the shared Approve/Reject
    # buttons, which are modality-agnostic so they live here once rather
    # than being duplicated in every modality control.
    class DetailPaneControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      # rubocop:disable Metrics/BlockLength
      body {
        vertical_box {
          label {
            # rubocop:disable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Modality: #{item[:modality]}" : "" }]
            # rubocop:enable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          }
          label {
            # rubocop:disable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Reason: #{item[:reason]}" : "" }]
            # rubocop:enable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          }
          label {
            # rubocop:disable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Source: #{item[:source_file]}" : "" }]
            # rubocop:enable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          }
          label {
            # rubocop:disable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Created: #{item[:created_at]}" : "" }]
            # rubocop:enable Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          }

          image_review_control(viewmodel:)
          text_review_control(viewmodel:)

          # Exhaustiveness fallback (SIFT Finding 1): an unrecognized modality
          # shows an explicit message instead of a silent blank pane — the
          # complement of both review controls' visible bindings, all three
          # reading the same viewmodel.detail_kind single source of truth.
          label {
            # rubocop:disable Style/HashAsLastArrayItem
            unrecognized_message = lambda { |kind|
              next "" unless kind == :unrecognized

              "No reviewer UI for modality #{viewmodel.selected_item[:modality].inspect} yet."
            }
            text <= [viewmodel, :detail_kind, on_read: unrecognized_message]
            # rubocop:enable Style/HashAsLastArrayItem
          }

          # rubocop:disable Style/StringLiterals
          button('Approve') {
            # rubocop:enable Style/StringLiterals
            # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]
            # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

            on_clicked do
              result = viewmodel.approve!
              # rubocop:disable Style/StringLiterals
              msg_box_error('Approve failed', result.failure.inspect) if result.failure?
              # rubocop:enable Style/StringLiterals
            end
          }

          # rubocop:disable Style/StringLiterals
          button('Reject') {
            # rubocop:enable Style/StringLiterals
            # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]
            # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

            on_clicked do
              result = viewmodel.reject!
              # rubocop:disable Style/StringLiterals
              msg_box_error('Reject failed', result.failure.inspect) if result.failure?
              # rubocop:enable Style/StringLiterals
            end
          }
        }
      }
      # rubocop:enable Metrics/BlockLength
    end
  end
end
