# frozen_string_literal: true

require "tty-progressbar"

module SFL
  module CLI
    # Replaces kb_progress_printer's plain puts with a TTY::ProgressBar row
    # plus a permanent bar.log() line per artifact — same pattern as
    # TurnProgressBar, for Analysis::KnowledgeBaseSource's single
    # on_progress callback (no separate start event; KB artifacts are
    # bulk-listed upfront, unlike a conversation's turn-by-turn dispatch).
    class ArtifactProgressBar
      FORMAT = "[:bar] :current/:total :percent (:eta remaining)"

      # @param event [Hash] {artifact_id:, total:, title:, source_file:}
      def advance(event)
        @bar ||= TTY::ProgressBar.new(FORMAT, total: event[:total], hide_cursor: true)
        @bar.log("  #{event[:artifact_id]}/#{event[:total]} [#{File.basename(event[:source_file])}] #{event[:title]}")
        @bar.advance
      end
    end
  end
end
