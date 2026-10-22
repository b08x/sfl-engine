# frozen_string_literal: true

module SFL
  module TUI
    module Runs
      # View model: turns RunLog rows into the table cells the Runs tab
      # shows. Pure; the clock comes in as an argument.
      module Rows
        extend self

        HEADER = %w[started kind collection state progress failed item run].freeze

        # States drawn in a warning colour.
        ATTENTION = (Core::RunState::STALLED + %w[failed]).freeze

        # @param rows [Array<Hash>] RunLog#list rows, newest first, each with `state`
        # @param now [Time]
        # @return [Array<Array<String>>]
        def cells(rows, now:) = rows.map { |row| cell(row, now) }

        # @return [Array<String>] one row's cells
        def cell(row, now)
          [
            started(row[:started_at], now),
            row[:kind].to_s,
            row[:collection] || "-",
            row[:state].to_s,
            progress(row),
            row[:failed].to_i.to_s,
            row[:current_item].to_s,
            row[:run_id].to_s[0, 8],
          ]
        end

        # @return [String] "done/total (pct%)"
        def progress(row)
          done = row[:done].to_i
          total = row[:total].to_i
          return "#{done}/0" unless total.positive?

          "#{done}/#{total} (#{done * 100 / total}%)"
        end

        # @return [String] "HH:MM:SS" today, "YYYY-MM-DD HH:MM" before
        def started(time, now)
          return "-" unless time

          (time.to_date == now.to_date) ? time.strftime("%H:%M:%S") : time.strftime("%Y-%m-%d %H:%M")
        end

        # @return [Boolean] the row's state needs attention
        def attention?(row) = ATTENTION.include?(row[:state].to_s)
      end
    end
  end
end
