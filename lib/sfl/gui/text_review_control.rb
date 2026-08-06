# frozen_string_literal: true

# lib/sfl/gui/text_review_control.rb

require_relative "save_and_recompile_section"

module SFL
  module GUI
    # Same shape as ImageReviewControl minus the image — serves both
    # "text" and "audio" modalities identically (audio has no special
    # rendering need beyond its transcript text). visible is bound to
    # viewmodel.detail_kind, the same single source of truth
    # ImageReviewControl reads (SIFT Finding 1 fix).
    class TextReviewControl
      include Glimmer::LibUI::CustomControl
      include SaveAndRecompileSection

      options :viewmodel

      body {
        control = self

        vertical_box {
          # See ImageReviewControl for why computed_by is required here:
          # detail_kind has no writer, so without it Glimmer never observes it.
          visible <= [viewmodel, :detail_kind, on_read: ->(k) { k == :text }, computed_by: [:selected_item]]

          control.save_and_recompile_section
        }
      }
    end
  end
end
