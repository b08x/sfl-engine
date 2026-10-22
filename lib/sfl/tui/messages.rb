# frozen_string_literal: true

module SFL
  module TUI
    # Messages fed to Program.update: key presses from the event loop, and
    # the results commands return.
    module Messages
      # A key press, named the way RatatuiRuby::Event::Key#to_sym names it:
      # "a", "A", " ", "enter", "esc", "up", "ctrl_c".
      Key = Data.define(:key)

      # A one-line notice for the status line.
      Status = Data.define(:text)

      # A review decision or recompile finished; Browse reloads after it.
      Reviewed = Data.define(:text)

      # Browse's tree and review state, freshly read from the BrowseSource.
      BrowseLoaded = Data.define(:tree, :reviews)

      # One section's clauses.
      ClausesLoaded = Data.define(:section_id, :clauses)

      # An export finished.
      Exported = Data.define(:path, :count)

      # Search results, each row a Hash with `collection:`, `document_key:`,
      # `section:` and the RetrievalResult fields.
      SearchResults = Data.define(:query, :rows)

      # RunLog rows, newest first, each with a `state`.
      RunsLoaded = Data.define(:rows)

      # The Models tab's data: one row per task (Models::Rows.tasks), every
      # listed model (ModelStore#list), and an optional notice from the
      # assign or refresh that preceded the load.
      ModelsLoaded = Data.define(:tasks, :models, :notice)

      # An ingest started from the launcher: in a new kitty tab, or as a
      # detached child (`detached: true`) whose run the Runs tab shows.
      Launched = Data.define(:text, :detached)

      # The event loop's clock: sent when a poll for input timed out, so
      # tabs that poll (Runs) can refresh.
      Tick = Data.define(:at)

      # The single failure channel: a command that raised returns this, and
      # the status line shows it.
      class Failed
        # Any run of whitespace, newlines included: the status line is one row.
        WHITESPACE = /\s+/

        attr_reader :source, :detail

        # @param source [Symbol] which tab or collaborator failed
        # @param detail [String] operator-facing text; whitespace is collapsed
        def initialize(source, detail)
          @source = source
          @detail = detail.to_s.gsub(WHITESPACE, " ").strip
          freeze
        end

        def to_s = "#{source}: #{detail}"
      end
    end
  end
end
