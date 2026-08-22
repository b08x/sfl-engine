# frozen_string_literal: true

module SFL
  module TUI
    module Workspaces
      # §2.2 — Review Queues. Three columns at 30/45/25: the queue list, the
      # full clause/content detail, and the before/after annotation diff. The
      # list gets more width than the Query Console's because queue rows carry
      # a status glyph and a document label, not just a question string.
      #
      # Phase 3 wires this to Store::PgAnnotationReviewRepository and
      # Store::PgReviewQueueRepository.
      class ReviewQueue < Base
        def title = "Review Queues"

        def view(context)
          height = Layout.body_height(context)
          list_width, detail_width, diff_width = Layout.columns(context.width, 0.30, 0.45, 0.25)

          row(
            pane("Queue", pending("content / annotation review"), width: list_width, height:),
            pane("Detail", pending("tokens · ideational · interpersonal"), width: detail_width, height:),
            pane("Diff", pending("mood · tenor · modality"), width: diff_width, height:)
          )
        end
      end
    end
  end
end
