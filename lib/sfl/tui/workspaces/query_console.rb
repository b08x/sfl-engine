# frozen_string_literal: true

module SFL
  module TUI
    module Workspaces
      # §2.1 — Query Console. Three columns at 25/50/25: the recent-query ring
      # buffer, the synthesized answer, and the retrieval trace. The centre
      # column splits 70/30 vertically so the rrf_score telemetry row has a
      # home under the answer without stealing width from the trace pane.
      #
      # Phase 2 wires this to Analysis::ContextSynthesizer and
      # Store::PgHybridRetriever. Phase 1 draws the panes only.
      class QueryConsole < Base
        def title = "Query Console"

        def view(context)
          height = Layout.body_height(context)
          sessions_width, centre_width, trace_width = Layout.columns(context.width, 0.25, 0.50, 0.25)
          answer_height, telemetry_height = Layout.rows(height, 0.70, 0.30)

          row(
            pane("Recent Queries", pending("session ring buffer"), width: sessions_width, height:),
            stack(
              pane("Answer", pending("cited synthesis (glamour)"), width: centre_width, height: answer_height),
              pane("Telemetry", pending("rrf_score per clause"), width: centre_width, height: telemetry_height)
            ),
            pane("Retrieval Trace", pending("semantic vs keyword rank"), width: trace_width, height:)
          )
        end
      end
    end
  end
end
