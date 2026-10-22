# frozen_string_literal: true

module SFL
  module TUI
    module Launcher
      # Draws the launcher as an overlay centred on the tab body.
      module View
        extend self

        WIDTH = 72
        HEIGHT = 11
        LABELS = { path: "Path", collection: "Collection", flags: "Flags" }.freeze

        # @return [Array<String>]
        def lines(state)
          fields = FIELDS.map do |field|
            marker = (state.focus == field) ? ">" : " "
            "#{marker} #{LABELS.fetch(field).ljust(11)} #{state.public_send(field)}#{suffix(state, field)}"
          end
          existing = state.collections.empty? ? "none" : state.collections.join(", ")
          [
            "Ingest a file or folder into a collection",
            "",
            *fields,
            "",
            "Existing collections: #{existing}",
            state.error ? "! #{state.error}" : "Flags: --output-dir DIR, --disable-tracing",
          ]
        end

        def render(state, frame, area, tui)
          width = [WIDTH, area.width].min
          height = [HEIGHT, area.height].min
          rect = tui.rect(x: area.x + ((area.width - width) / 2), y: area.y + ((area.height - height) / 2), width:, height:)
          text = tui.paragraph(text: lines(state).join("\n"), block: tui.block(title: "Ingest", borders: [:all],
            border_style: tui.style(fg: :cyan)))
          frame.render_widget(tui.overlay(layers: [tui.clear, text]), rect)
        end

        private def suffix(state, field)
          return "" unless field == :collection

          return "  (existing)" if state.existing?

          state.collection.strip.empty? ? "  (default: the path's base name)" : "  (new)"
        end
      end
    end
  end
end
