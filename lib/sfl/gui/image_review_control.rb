# lib/sfl/gui/image_review_control.rb
# frozen_string_literal: true

require_relative "failure_message"

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

      IMAGE_WIDTH = 400
      IMAGE_HEIGHT = 400

      # glimmer-dsl-libui rasterizes images through ChunkyPNG, which reads PNG
      # only. Anything else — a nil path, a file that has since been moved, a
      # JPEG — makes ImageProxy#draw raise from inside the libui draw callback,
      # where no Ruby rescue can reach it. So the path is validated up front and
      # nothing is drawn unless it will actually load.
      PREVIEWABLE_EXTENSION = ".png"

      attr_accessor :image_area

      body {
        control = self

        vertical_box {
          # computed_by is load-bearing, not decoration: detail_kind is a
          # derived reader with no writer, and Glimmer only observes properties
          # that have a writer or an explicit computed_by. Without it this
          # binding evaluates once at construction (when nothing is selected)
          # and never fires again.
          # rubocop:disable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral
          visible <= [viewmodel, :detail_kind, on_read: ->(k) { k == :image }, computed_by: [:selected_item]]
          # rubocop:enable Lint/Void, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral

          # The image is drawn imperatively inside on_draw rather than declared
          # as a static child. A child `image` proxy caches its rasterized
          # shapes and is drawn unconditionally by its area — including when its
          # path is nil, which crashes. Drawing per-frame re-reads the current
          # selection and simply draws nothing when there is no usable file.
          control.image_area = area {
            on_draw do |_area_draw_params|
              path = control.previewable_image_path
              image(path, IMAGE_WIDTH, IMAGE_HEIGHT) if path
            end
          }

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

      after_body {
        # on_draw only re-runs when a redraw is requested, and selecting a
        # different row changes no area property that would request one. This
        # observer is what turns a selection change into a repaint.
        @selection_observer = Glimmer::DataBinding::Observer.proc { image_area&.queue_redraw_all }
        @selection_observer.observe(viewmodel, :selected_item)
      }

      # @return [String, nil] the selected row's source file if it can be
      #   rasterized, nil if there is nothing safe to draw
      def previewable_image_path
        path = viewmodel.selected_item&.dig(:source_file)
        return nil if path.nil?
        return nil unless path.downcase.end_with?(PREVIEWABLE_EXTENSION)
        return nil unless File.exist?(path)

        path
      end
    end
  end
end
