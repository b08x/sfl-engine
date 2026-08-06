# frozen_string_literal: true

# lib/sfl/gui/detail_pane_control.rb

require_relative "failure_message"
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
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Modality: #{item[:modality]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Reason: #{item[:reason]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Source: #{item[:source_file]}" : "" }]
          }
          label {
            text <= [viewmodel, :selected_item, on_read: ->(item) { item ? "Created: #{item[:created_at]}" : "" }]
          }

          image_review_control(viewmodel:)
          text_review_control(viewmodel:)

          # Exhaustiveness fallback (SIFT Finding 1): an unrecognized modality
          # shows an explicit message instead of a silent blank pane — the
          # complement of both review controls' visible bindings, all three
          # reading the same viewmodel.detail_kind single source of truth.
          label {
            unrecognized_message = lambda { |kind|
              next "" unless kind == :unrecognized

              "No reviewer UI for modality #{viewmodel.selected_item[:modality].inspect} yet."
            }
            # computed_by is required: detail_kind is a writer-less derived
            # reader, which Glimmer will not observe on its own.
            text <= [viewmodel, :detail_kind, on_read: unrecognized_message, computed_by: [:selected_item]]
          }

          button("Approve") {
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]

            on_clicked do
              result = viewmodel.approve!
              msg_box_error("Approve failed", FailureMessage.call(result.failure)) if result.failure?
            end
          }

          button("Reject") {
            enabled <= [viewmodel, :selected_item, on_read: ->(item) { !item.nil? }]

            on_clicked do
              result = viewmodel.reject!
              msg_box_error("Reject failed", FailureMessage.call(result.failure)) if result.failure?
            end
          }
        }
      }
      # rubocop:enable Metrics/BlockLength
    end
  end
end
