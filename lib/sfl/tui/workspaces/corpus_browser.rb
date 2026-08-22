# frozen_string_literal: true

module SFL
  module TUI
    module Workspaces
      # §2.3 — Corpus Browser, in the plain-filtered-clause-table form §2.3
      # settles on rather than the speculative Cartographer drill-down. Two
      # columns at 35/65: filter bar plus clause list, and clause detail. No
      # third pane, because there is no trace or diff to show on a read-only
      # browse.
      #
      # Phase 5 wires this to Store::PgClauseStore's existing filter contract.
      class CorpusBrowser < Base
        def title = "Corpus Browser"

        def view(context)
          height = Layout.body_height(context)
          list_width, detail_width = Layout.columns(context.width, 0.35, 0.65)

          row(
            pane("Clauses", pending("filtered, paginated"), width: list_width, height:),
            pane("Clause Detail", pending("payloads · reasoning trace"), width: detail_width, height:)
          )
        end
      end
    end
  end
end
