# frozen_string_literal: true

module SFL
  module TUI
    module Browse
      # Draws the Browse tab: tree, clause list and detail side by side,
      # plus the export format choice when it is open.
      module View
        extend self

        WIDTHS = [30, 35, 35].freeze
        OVERLAY_TEXT = "Export selected clauses as:\n\n  j  JSONL\n  m  Markdown\n\n  Esc  cancel"

        # @param state [State]
        # @param frame [RatatuiRuby::Frame]
        # @param area [RatatuiRuby::Layout::Rect]
        # @param tui [RatatuiRuby::TUI]
        def render(state, frame, area, tui)
          constraints = WIDTHS.map { |percent| tui.constraint_percentage(percent) }
          tree_area, clause_area, detail_area = tui.layout_split(area, direction: :horizontal, constraints:)
          frame.render_widget(tree_list(state, tui), tree_area)
          frame.render_widget(clause_list(state, tui), clause_area)
          frame.render_widget(detail(state, tui), detail_area)
          render_overlay(frame, area, tui) if state.overlay == :export
        end

        private def tree_list(state, tui)
          items = state.rows.map { |node| Rows.tree_label(state, node) }
          title = "Tree [#{StatusFilter.label(state.filter)}]"
          list(tui, items, state.rows.empty? ? nil : state.cursor, title, state.focus == :tree)
        end

        private def clause_list(state, tui)
          rows = state.clause_rows
          selected = (state.focus == :clauses && rows.any?) ? state.clause_cursor : nil
          list(tui, rows.map { |node| Rows.clause_label(state, node) }, selected, "Clauses", state.focus == :clauses)
        end

        private def list(tui, items, selected_index, title, focused)
          tui.list(
            items:, selected_index:, highlight_symbol: "> ",
            highlight_style: tui.style(modifiers: [:reversed]),
            block: tui.block(title:, borders: [:all], border_style: tui.style(fg: focused ? :cyan : :dark_gray))
          )
        end

        private def detail(state, tui)
          tui.paragraph(text: Detail.lines(state).join("\n"), wrap: true, block: tui.block(title: "Detail", borders: [:all]))
        end

        private def render_overlay(frame, area, tui)
          width = [34, area.width].min
          height = [8, area.height].min
          rect = tui.rect(x: area.x + ((area.width - width) / 2), y: area.y + ((area.height - height) / 2), width:, height:)
          frame.render_widget(tui.clear, rect)
          frame.render_widget(tui.paragraph(text: OVERLAY_TEXT, block: tui.block(title: "Export", borders: [:all])), rect)
        end
      end
    end
  end
end
