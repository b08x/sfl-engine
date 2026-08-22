# frozen_string_literal: true

require "lipgloss"

module SFL
  module TUI
    # Every lipgloss Style the TUI renders with, in one place, so panes stay
    # visually consistent and no workspace hand-rolls ANSI.
    #
    # Note the border constants are SYMBOLS on Lipgloss::Border
    # (Border::ROUNDED), not the `Border.rounded` builder methods the Go API
    # exposes — that difference is the single most common porting mistake
    # against lipgloss-ruby.
    module Theme
      extend self

      ACCENT = "#7D56F4"
      MUTED = "#6C7086"
      ALERT = "#F38BA8"

      # @param width [Integer] TOTAL pane width including its border
      # @param height [Integer] TOTAL pane height including its border
      # @param active [Boolean] whether this pane belongs to the focused workspace
      def pane(width:, height:, active: false)
        Lipgloss::Style.new
          .border(Lipgloss::Border::ROUNDED)
          .border_foreground(active ? ACCENT : MUTED)
          .padding(0, 1)
          .width([width - 2, 1].max)
          .height([height - 2, 1].max)
          # width/height are MINIMUMS in lipgloss — content longer than the box
          # expands it, which on a narrow terminal turns a wrapped placeholder
          # into a pane taller than the screen. The max_* pair is what actually
          # bounds the frame.
          .max_width(width)
          .max_height(height)
      end

      def pane_title(text) = Lipgloss::Style.new.bold(true).foreground(ACCENT).render(text)

      def tab(text, active:)
        style = Lipgloss::Style.new.padding(0, 2)
        active ? style.bold(true).foreground(ACCENT).underline(true).render(text) : style.foreground(MUTED).render(text)
      end

      def status(text) = Lipgloss::Style.new.faint(true).render(text)

      def error(text) = Lipgloss::Style.new.bold(true).foreground(ALERT).render(text)

      def placeholder(text) = Lipgloss::Style.new.faint(true).render(text)
    end
  end
end
