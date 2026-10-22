# frozen_string_literal: true

module SFL
  module CLI
    # Turns the progress callbacks of Analysis::Engine (#start/#advance) and
    # Analysis::KnowledgeBaseSource (#artifact/#artifact_done) into
    # Core::Ports::ProgressSink calls. The sink is CLI::PgRunProgressSink for
    # the `runs` table, wrapped in a Dashboard::Sink when the dashboard is
    # drawn. The stderr line `progress turn=N total=M` is written by
    # Analysis::Engine, not here.
    #
    # Sinks may also answer #item(name) (the item now in progress) and
    # #note(clauses:, defaulted:) (what a finished item wrote); both are
    # optional.
    class CompositeProgress
      # @param sink [Core::Ports::ProgressSink]
      def initialize(sink:)
        @sink = sink
      end

      # Engine's on_turn_start: {turn_id:, total:, speaker:}
      def start(event)
        @sink.start(event[:total]) if event[:turn_id] == 1
        item(event[:speaker])
      end

      # Engine's on_progress: {turn_id:, total:, clause_count:, defaulted:, ...}
      def advance(event)
        @sink.advance(by: 1)
        note(event)
      end

      # KnowledgeBaseSource's on_progress, called before each artifact compiles:
      # {artifact_id:, total:, title:, source_file:}
      def artifact(event)
        @sink.start(event[:total]) if event[:artifact_id] == 1
        item(event[:source_file])
      end

      # KnowledgeBaseSource's on_artifact_done, called after each artifact
      # compiles or is skipped: {artifact_id:, total:, failed:, clause_count:, defaulted:}
      def artifact_done(event)
        @sink.advance(by: 1, failed: event[:failed] ? 1 : 0)
        note(event)
      end

      private def item(name) = (@sink.item(name) if @sink.respond_to?(:item))

      private def note(event)
        return unless @sink.respond_to?(:note)

        @sink.note(clauses: event[:clause_count].to_i, defaulted: event[:defaulted].to_i)
      end
    end
  end
end
