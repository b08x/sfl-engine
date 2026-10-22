# frozen_string_literal: true

module SFL
  module TUI
    # The Search tab: runs the stored-clause retrieval and shows each hit
    # with its collection, document and section.
    module Search
      TITLE = "Search"
      HELP = "/ type query · Enter search · Esc stop typing · ↑/↓ move"
      LIMIT = 20

      State = Data.define(:query, :editing, :results, :cursor)

      extend self

      def initial = State.new(query: "", editing: false, results: [], cursor: 0)

      def init(_services) = nil

      def handles?(message) = message.is_a?(Messages::SearchResults)

      # While typing, every key goes into the query.
      def capturing?(state) = state.editing

      def help(_state) = HELP

      def status(state) = state.results.empty? ? nil : "#{state.results.size} results for #{state.query.inspect}"

      # @return [Array(State, Proc|nil)]
      def update(state, message, services)
        case message
        when Messages::SearchResults then [state.with(query: message.query, results: message.rows, cursor: 0), nil]
        when Messages::Key then state.editing ? edit(state, message.key, services) : browse(state, message.key)
        else [state, nil]
        end
      end

      # @return [Proc] -> Messages::SearchResults
      def run(services, query)
        SafeCommand.wrap(source: :search, logger: services.logger) do
          hits = services.retriever.retrieve(Core::Types::RetrievalQuery.new(query:, limit: LIMIT))
          places = services.source.locate(hits.filter_map(&:section_id).uniq)
          rows = hits.map do |hit|
            place = places.fetch(hit.section_id, {})
            {
              collection: place[:collection],
              document_key: place[:document_key],
              section: place[:label] || hit.section_id,
              section_id: hit.section_id,
              text: hit.text,
              score: hit.rrf_score,
            }
          end
          Messages::SearchResults.new(query:, rows:)
        end
      end

      def edit(state, key, services)
        case key
        when "enter" then [state.with(editing: false), state.query.strip.empty? ? nil : run(services, state.query.strip)]
        when "esc" then [state.with(editing: false), nil]
        when "backspace" then [state.with(query: state.query[0...-1]), nil]
        else [(key.length == 1) ? state.with(query: state.query + key) : state, nil]
        end
      end

      def browse(state, key)
        last = [state.results.size - 1, 0].max
        case key
        when "/" then [state.with(editing: true), nil]
        when "up", "k" then [state.with(cursor: (state.cursor - 1).clamp(0, last)), nil]
        when "down", "j" then [state.with(cursor: (state.cursor + 1).clamp(0, last)), nil]
        else [state, nil]
        end
      end

      def render(state, frame, area, tui)
        input_area, results_area = tui.layout_split(area, direction: :vertical,
          constraints: [tui.constraint_length(3), tui.constraint_fill(1)])
        cursor = state.editing ? "_" : ""
        frame.render_widget(tui.paragraph(text: "#{state.query}#{cursor}", block: tui.block(title: "Query", borders: [:all])),
          input_area)
        frame.render_widget(results_table(state, tui), results_area)
      end

      def results_table(state, tui)
        rows = state.results.map do |row|
          [
            format("%.3f", row[:score].to_f),
            row[:collection].to_s,
            row[:document_key].to_s,
            row[:section].to_s,
            row[:text].to_s.tr("\n", " "),
]
        end
        tui.table(
          header: %w[score collection document section text], rows:,
          widths: [
            tui.constraint_length(6),
            tui.constraint_percentage(15),
            tui.constraint_percentage(20),
            tui.constraint_percentage(15),
            tui.constraint_fill(1),
],
          selected_row: rows.empty? ? nil : state.cursor, row_highlight_style: tui.style(modifiers: [:reversed]),
          block: tui.block(title: "Results", borders: [:all])
        )
      end
    end
  end
end
