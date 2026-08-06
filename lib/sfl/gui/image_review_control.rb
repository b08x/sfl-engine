# frozen_string_literal: true

# lib/sfl/gui/image_review_control.rb

require_relative "save_and_recompile_section"

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
      include SaveAndRecompileSection

      options :viewmodel

      # The preview box the image is fitted inside, not the size it is drawn at
      # — see #preview_geometry.
      MAX_PREVIEW_WIDTH = 400
      MAX_PREVIEW_HEIGHT = 400

      # glimmer-dsl-libui rasterizes images through ChunkyPNG, which reads PNG
      # only. Anything else — a nil path, a file that has since been moved, a
      # JPEG — makes ImageProxy#draw raise from inside the libui draw callback,
      # where no Ruby rescue can reach it. So the path is validated up front and
      # nothing is drawn unless it will actually load.
      PREVIEWABLE_EXTENSION = ".png"

      # Bytes 16..23 of a PNG are the IHDR width and height, big-endian uint32
      # each. Read directly rather than through ChunkyPNG so getting the
      # dimensions doesn't decode the whole image on every repaint.
      PNG_HEADER_BYTES = 24
      PNG_DIMENSION_OFFSET = 16

      attr_accessor :image_area

      body {
        control = self

        vertical_box {
          # computed_by is load-bearing, not decoration: detail_kind is a
          # derived reader with no writer, and Glimmer only observes properties
          # that have a writer or an explicit computed_by. Without it this
          # binding evaluates once at construction (when nothing is selected)
          # and never fires again.
          visible <= [viewmodel, :detail_kind, on_read: ->(k) { k == :image }, computed_by: [:selected_item]]

          # The image is drawn imperatively inside on_draw rather than declared
          # as a static child. A child `image` proxy caches its rasterized
          # shapes and is drawn unconditionally by its area — including when its
          # path is nil, which crashes. Drawing per-frame re-reads the current
          # selection and simply draws nothing when there is no usable file.
          control.image_area = area {
            on_draw do |_area_draw_params|
              path, width, height = control.preview_geometry
              image(path, width, height) if path
            end
          }

          control.save_and_recompile_section
        }
      }

      after_body {
        # on_draw only re-runs when a redraw is requested, and selecting a
        # different row changes no area property that would request one. This
        # observer is what turns a selection change into a repaint.
        #
        # SIFT F-5: deliberately never unobserved. This control is constructed
        # once, by DetailPaneControl, and lives for the life of the window — it
        # is not rebuilt per selection — so the observer's lifetime already is
        # the process's lifetime and there is no leak to dispose of. Adding
        # teardown here would be dead code guarding an unreachable case.
        @selection_observer = Glimmer::DataBinding::Observer.proc { image_area&.queue_redraw_all }
        @selection_observer.observe(viewmodel, :selected_item)
      }

      # SIFT S-3: previously drawn at a fixed 400x400, which stretched any
      # non-square source out of shape. Scales to fit inside the preview box
      # instead, preserving the source aspect ratio. Never enlarges: a 64px
      # icon blown up to 400px is worse to review than the same icon at 64px.
      #
      # Falls back to the box size when the header can't be read, which keeps a
      # readable (if distorted) preview rather than showing nothing at all.
      #
      # @return [Array(String, Integer, Integer), nil] path, draw width, draw
      #   height — or nil when there is nothing safe to draw
      def preview_geometry
        path = previewable_image_path
        return nil if path.nil?

        source = png_dimensions(path)
        return [path, MAX_PREVIEW_WIDTH, MAX_PREVIEW_HEIGHT] if source.nil?

        width, height = source
        scale = [MAX_PREVIEW_WIDTH.fdiv(width), MAX_PREVIEW_HEIGHT.fdiv(height), 1.0].min
        [path, (width * scale).round, (height * scale).round]
      end

      # @return [String, nil] the selected row's source file if it can be
      #   rasterized, nil if there is nothing safe to draw
      def previewable_image_path
        path = viewmodel.selected_item&.dig(:source_file)
        return nil if path.nil?
        return nil unless path.downcase.end_with?(PREVIEWABLE_EXTENSION)
        return nil unless File.exist?(path)

        path
      end

      # Runs inside the libui draw callback, where a raised exception can't be
      # caught by anything upstream, so every failure resolves to nil instead.
      #
      # @return [Array(Integer, Integer), nil] source width and height
      private def png_dimensions(path)
        header = File.binread(path, PNG_HEADER_BYTES)
        return nil unless header&.bytesize == PNG_HEADER_BYTES

        # A full-length header guarantees unpack returns two integers.
        width, height = header.byteslice(PNG_DIMENSION_OFFSET, 8).unpack("N2")
        return nil if width.zero? || height.zero?

        [width, height]
      rescue
        nil
      end
    end
  end
end
