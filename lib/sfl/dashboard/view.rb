# frozen_string_literal: true

module SFL
  module Dashboard
    # Draws one State: header, ingest and annotation panels, the log, and a
    # key-hint line. Pure: everything shown comes from the State.
    module View
      extend self

      HEADER_ROWS = 4
      PANEL_ROWS = 9
      HINT_RUNNING = "Ctrl-C stop gracefully after the current item"
      HINT_STOPPING = "stopping after the current item · Ctrl-C again to quit now"
      HINT_DONE = "press any key to exit"

      # @param frame [RatatuiRuby::Frame]
      # @param tui [RatatuiRuby::TUI]
      def render(state, frame, tui)
        header, panels, events, hint = tui.layout_split(frame.area, direction: :vertical,
          constraints: [
            tui.constraint_length(HEADER_ROWS),
            tui.constraint_length(PANEL_ROWS),
            tui.constraint_fill(1),
            tui.constraint_length(1),
])
        ingest, annotation = tui.layout_split(panels, direction: :horizontal,
          constraints: [tui.constraint_percentage(50), tui.constraint_percentage(50)])
        frame.render_widget(tui.paragraph(text: header_lines(state), wrap: true, block: tui.block(title: title(state), borders: [:all])),
          header)
        ingest_panel(state, frame, ingest, tui)
        annotation_panel(state, frame, annotation, tui)
        frame.render_widget(log_panel(state, events, tui), events)
        frame.render_widget(tui.paragraph(text: hint(state), style: tui.style(fg: :dark_gray)), hint)
      end

      def title(state) = "sfl #{state.kind} · #{state.outcome || (state.stopping ? 'stopping' : 'running')}"

      # @return [Array<String>] run id, collection, elapsed time and models
      def header_lines(state)
        [
          "run #{state.run_id} · collection #{state.collection || '-'} · elapsed #{duration(state.elapsed)}",
          "models: #{state.models.empty? ? '-' : state.models.join(' · ')}",
        ]
      end

      # @return [Array<String>] the ingest panel's text rows
      def ingest_lines(state)
        [
          "documents #{state.documents_done}/#{state.documents_total || state.documents_started}",
          "sections #{state.sections_done}/#{state.sections_total}",
          "clauses written #{state.clauses}",
          "rate #{format('%.1f', state.rate)} sections/min · ETA #{duration(state.run_eta)}",
          "failures #{state.failures}",
          "current #{state.current_item || '-'}",
        ]
      end

      # @return [Array<String>] the annotation panel's text rows
      def annotation_lines(state)
        [
          "turns #{state.doc_done}/#{state.doc_total} in this document",
          "defaulted #{state.defaulted}",
          "429 backoffs #{state.backoffs}",
          "ETA #{duration(state.document_eta)}",
        ]
      end

      def hint(state)
        return "#{state.outcome} · #{HINT_DONE}" if state.outcome

        state.stopping ? HINT_STOPPING : HINT_RUNNING
      end

      # @param seconds [Numeric, nil]
      # @return [String] "1:02:03", "02:03", or "-" when unknown
      def duration(seconds)
        return "-" unless seconds

        total = seconds.round
        hours, rest = total.divmod(3600)
        minutes, secs = rest.divmod(60)
        hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%02d:%02d", minutes, secs)
      end

      # @return [Float] 0.0..1.0
      def ratio(done, total) = total.to_i.positive? ? (done.to_f / total).clamp(0.0, 1.0) : 0.0

      private def ingest_panel(state, frame, area, tui)
        documents_total = state.documents_total || state.documents_started
        panel(frame, area, tui, "Ingest", ingest_lines(state)) do |gauge_area|
          frame.render_widget(tui.gauge(ratio: ratio(state.documents_done, documents_total),
            label: "#{state.documents_done}/#{documents_total} documents"), gauge_area)
        end
      end

      private def annotation_panel(state, frame, area, tui)
        panel(frame, area, tui, "Annotation", annotation_lines(state)) do |gauge_area|
          frame.render_widget(tui.line_gauge(ratio: ratio(state.doc_done, state.doc_total),
            label: "#{state.doc_done}/#{state.doc_total}"), gauge_area)
        end
      end

      private def panel(frame, area, tui, name, lines)
        block = tui.block(title: name, borders: [:all])
        frame.render_widget(block, area)
        gauge_area, text_area = tui.layout_split(block.inner(area), direction: :vertical,
          constraints: [tui.constraint_length(1), tui.constraint_fill(1)])
        yield gauge_area
        frame.render_widget(tui.paragraph(text: lines), text_area)
      end

      private def log_panel(state, area, tui)
        visible = [area.height - 2, 0].max
        tui.paragraph(text: state.log.last(visible), block: tui.block(title: "Log", borders: [:all]))
      end
    end
  end
end
