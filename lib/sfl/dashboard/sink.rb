# frozen_string_literal: true

module SFL
  module Dashboard
    # ProgressSink decorator: records every call on the Board and forwards
    # it to the wrapped sink (CLI::PgRunProgressSink), so the dashboard and
    # the `runs` table see the same events.
    class Sink
      include Core::Ports::ProgressSink

      # @param inner [Core::Ports::ProgressSink]
      # @param board [Board]
      def initialize(inner:, board:)
        @inner = inner
        @board = board
      end

      def start(total)
        @board.update { |state| state.start(total) }
        @inner.start(total)
      end

      def advance(by: 1, failed: 0)
        @board.update { |state| state.advance(by:, failed:) }
        @inner.advance(by:, failed:)
      end

      # @param name [String] the item now in progress
      def item(name)
        @board.update { |state| state.item(name) }
        @inner.item(name) if @inner.respond_to?(:item)
      end

      # @param clauses [Integer]
      # @param defaulted [Integer]
      def note(clauses:, defaulted:)
        @board.update { |state| state.note(clauses:, defaulted:) }
      end

      # @param status [String] "finished", "failed" or "interrupted"
      def finish(status: "finished")
        @board.update { |state| state.finish(status) }
        @inner.finish(status:)
      end
    end
  end
end
