# frozen_string_literal: true

module SFL
  module TUI
    module Workspaces
      # §2.4 — Trackboi board. Four equal columns, one per board column, which
      # is where this workspace's proportions differ from the other three: a
      # Kanban has no primary pane to give the widest share to.
      #
      # Phase 4 renders these READ-ONLY from .trackboi/* (sanctioned by
      # trackboi's own SKILL.md). Every mutation must go through trackboi's MCP
      # server — never a file write — so no write path is stubbed here.
      class Board < Base
        COLUMN_COUNT = 4

        def title = "Board"

        def view(context)
          height = Layout.body_height(context)
          fractions = Array.new(COLUMN_COUNT, 1.0 / COLUMN_COUNT)
          widths = Layout.columns(context.width, *fractions)

          row(*widths.map { |width| pane("Column", pending("cards (read-only)"), width:, height:) })
        end
      end
    end
  end
end
