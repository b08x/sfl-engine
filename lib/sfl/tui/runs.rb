# frozen_string_literal: true

module SFL
  module TUI
    # The Runs tab: every run in the `runs` table (ingest, annotate, export,
    # recompile), newest first, with stalled and dead runs marked. It
    # re-reads the RunLog every POLL_SECONDS on the event loop's Tick.
    module Runs
      TITLE = "Runs"
      HELP = "↑/↓ move · r reload"
      POLL_SECONDS = 2
      LIMIT = 50

      # - `polled_at`: when the last load was asked for, nil before the first
      State = Data.define(:rows, :cursor, :polled_at, :now)

      extend self

      def initial = State.new(rows: [], cursor: 0, polled_at: nil, now: Time.now)

      # @return [Proc] the first load
      def init(services) = load(services)

      def handles?(message) = message.is_a?(Messages::RunsLoaded) || message.is_a?(Messages::Tick)

      def capturing?(_state) = false

      def help(_state) = HELP

      # @return [String, nil] how many runs need attention
      def status(state)
        stalled = state.rows.count { |row| Rows.attention?(row) }
        "#{state.rows.size} runs, #{stalled} stalled, dead or failed" unless state.rows.empty?
      end

      # @return [Array(State, Proc|nil)]
      def update(state, message, services)
        case message
        when Messages::RunsLoaded then [loaded(state, message.rows), nil]
        when Messages::Tick then tick(state, message.at, services)
        when Messages::Key then key(state, message.key, services)
        else [state, nil]
        end
      end

      # @return [Proc] -> Messages::RunsLoaded
      def load(services)
        SafeCommand.wrap(source: :runs, logger: services.logger) { Messages::RunsLoaded.new(services.run_log.list(limit: LIMIT)) }
      end

      def loaded(state, rows) = state.with(rows:, cursor: state.cursor.clamp(0, [rows.size - 1, 0].max))

      def tick(state, at, services)
        state = state.with(now: at)
        return [state, nil] if state.polled_at && at - state.polled_at < POLL_SECONDS

        [state.with(polled_at: at), load(services)]
      end

      def key(state, key, services)
        last = [state.rows.size - 1, 0].max
        case key
        when "up", "k" then [state.with(cursor: (state.cursor - 1).clamp(0, last)), nil]
        when "down", "j" then [state.with(cursor: (state.cursor + 1).clamp(0, last)), nil]
        when "r" then [state, load(services)]
        else [state, nil]
        end
      end

      def render(state, frame, area, tui)
        rows = state.rows.map do |row|
          cells = Rows.cell(row, state.now)
          Rows.attention?(row) ? tui.table_row(cells:, style: tui.style(fg: :yellow)) : cells
        end
        frame.render_widget(table(state, rows, tui), area)
      end

      private def table(state, rows, tui)
        tui.table(
          header: Rows::HEADER, rows:,
          widths: [
            tui.constraint_length(19),
            tui.constraint_length(9),
            tui.constraint_percentage(15),
            tui.constraint_length(11),
            tui.constraint_length(16),
            tui.constraint_length(6),
            tui.constraint_fill(1),
            tui.constraint_length(8),
          ],
          selected_row: rows.empty? ? nil : state.cursor, row_highlight_style: tui.style(modifiers: [:reversed]),
          block: tui.block(title: TITLE, borders: [:all])
        )
      end
    end
  end
end
