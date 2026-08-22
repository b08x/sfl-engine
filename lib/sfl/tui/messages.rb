# frozen_string_literal: true

require "bubbletea"

module SFL
  module TUI
    # Custom messages the app injects into the MVU loop.
    #
    # Every one subclasses Bubbletea::Message and calls super() in its
    # initializer — omitting super() leaves the base message's own state
    # uninitialised and the runner drops the message silently.
    module Messages
      # The single failure channel. A command must NEVER raise: an exception on
      # a background command thread is swallowed by the runner after smearing a
      # backtrace across the frame, so collaborator failures are unwrapped from
      # a Dry::Monads Failure into this message and rendered as an explicit
      # error state instead.
      class Failed < Bubbletea::Message
        # Any run of whitespace — newlines included. An exception message from
        # PG/Sequel routinely carries embedded newlines, and a multi-line
        # status bar is a multi-row status bar: it pushes the workspace body
        # down and desynchronises the renderer. Collapsing here keeps the
        # detail readable; Program#clamp enforces the single row structurally.
        WHITESPACE = /\s+/

        attr_reader :source, :detail

        # @param source [Symbol] which workspace or collaborator failed
        # @param detail [String] operator-facing text; whitespace is collapsed
        #   to a single line before it reaches the chrome
        def initialize(source, detail)
          super()
          @source = source
          @detail = detail.to_s.gsub(WHITESPACE, " ").strip
        end

        def to_s = "#{source}: #{detail}"
      end
    end
  end
end
