# frozen_string_literal: true

module SFL
  module TUI
    module Models
      # Draws the Models tab: the task table on the left, the selected
      # task's candidate models on the right.
      module View
        extend self

        def render(state, frame, area, tui)
          left, right = tui.layout_split(area, direction: :horizontal,
            constraints: [tui.constraint_percentage(60), tui.constraint_fill(1)])
          frame.render_widget(task_table(state, tui), left)
          frame.render_widget(model_table(state, tui), right)
        end

        private def task_table(state, tui)
          rows = state.tasks.map do |task|
            cells = Rows.task_cell(task)
            next tui.table_row(cells:, style: tui.style(fg: :yellow)) if task[:unavailable]

            Rows.locked?(task) ? tui.table_row(cells:, style: tui.style(fg: :dark_gray)) : cells
          end
          widths = [26, 10].map { |width| tui.constraint_length(width) } +
            [tui.constraint_fill(1), tui.constraint_length(7), tui.constraint_fill(2)]
          selected = (state.focus == :tasks) ? state.cursor : nil
          table(tui, Rows::TASK_HEADER, rows, selected:, title: "Tasks", widths:)
        end

        private def model_table(state, tui)
          rows = state.candidates.map do |model|
            cells = Rows.model_cell(model)
            model[:available] ? cells : tui.table_row(cells:, style: tui.style(fg: :dark_gray))
          end
          title = state.task ? "Models (#{state.task[:capability]})" : "Models"
          widths = [tui.constraint_length(10), tui.constraint_fill(1), tui.constraint_length(8), tui.constraint_length(11)]
          selected = (state.focus == :models) ? state.model_cursor : nil
          table(tui, Rows::MODEL_HEADER, rows, selected:, title:, widths:)
        end

        private def table(tui, header, rows, selected:, title:, widths:)
          tui.table(header:, rows:, widths:, selected_row: rows.empty? ? nil : selected,
            row_highlight_style: tui.style(modifiers: [:reversed]), block: tui.block(title:, borders: [:all]))
        end
      end
    end
  end
end
