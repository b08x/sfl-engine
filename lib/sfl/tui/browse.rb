# frozen_string_literal: true

module SFL
  module TUI
    # The Browse tab: collections, documents and nested sections on the
    # left, the focused section's clauses in the middle, detail on the
    # right; inline content review, selection and export.
    #
    # Every tab module answers the same protocol, which Program relies on:
    # TITLE, initial, init, update, handles?, capturing?, help, status, render.
    module Browse
      TITLE = "Browse"

      HELP = "↑/↓ move · Tab pane · Enter expand · Space select · a select level · Esc clear · f filter · " \
        "e export · A approve · R reject · E edit · o open image · r reload"
      OVERLAY_HELP = "j JSONL · m Markdown · Esc cancel"

      HANDLED = [Messages::BrowseLoaded, Messages::ClausesLoaded, Messages::Reviewed].freeze

      # @return [String] the Tree node id of a section
      extend self

      def section_node(section_id) = "s:#{section_id}"

      # @return [String] the Tree node id of a clause
      def clause_node(clause_id) = "k:#{clause_id}"

      def initial = State.initial

      # @return [Proc] the first load
      def init(services) = Commands.load(services)

      def update(state, message, services) = Update.call(state, message, services)

      def handles?(message) = HANDLED.any? { |type| message.is_a?(type) }

      # While the export choice is open every key belongs to it.
      def capturing?(state) = !state.overlay.nil?

      def help(state) = state.overlay ? OVERLAY_HELP : HELP

      # @return [String] selection counts
      def status(state)
        counts = state.selection.counts(state.tree)
        "selected: #{counts[:sections]} sections, #{counts[:clauses]} clauses"
      end

      def render(state, frame, area, tui) = View.render(state, frame, area, tui)
    end
  end
end
