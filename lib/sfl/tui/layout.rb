# frozen_string_literal: true

module SFL
  module TUI
    # Integer pane arithmetic for the proportions
    # docs/tui-implementation-plan.md §2 gives each workspace.
    #
    # Kept separate from Theme and from the workspaces themselves because it is
    # the one part of the layout that is pure arithmetic and therefore the one
    # part worth asserting on in a spec without rendering anything: columns
    # must sum to EXACTLY the available width, or lipgloss's join_horizontal
    # produces a row wider than the terminal and the frame wraps.
    module Layout
      extend self

      # Rows of chrome the root Program draws around the workspace body:
      # one tab bar, one status bar.
      CHROME_HEIGHT = 2

      # @param total [Integer] the full available width
      # @param fractions [Array<Float>] must sum to 1.0
      # @return [Array<Integer>] widths summing to exactly `total`
      def columns(total, *fractions)
        widths = fractions[0..-2].map { |fraction| [(total * fraction).floor, 1].max }
        [*widths, [total - widths.sum, 1].max]
      end

      # @param total [Integer] the full available height
      # @param fractions [Array<Float>] must sum to 1.0
      # @return [Array<Integer>] heights summing to exactly `total`
      def rows(total, *fractions) = columns(total, *fractions)

      # @return [Integer] the height a workspace body may occupy
      def body_height(context) = [context.height - CHROME_HEIGHT, 1].max
    end
  end
end
