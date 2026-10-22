# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # The terminal emulator the TUI runs in, for what a plain terminal
      # cannot do: open a new tab running a command, and show an image.
      # KittyHost drives kitty's remote control; Null::TerminalHost does
      # nothing and answers false, so callers fall back (decision 14).
      module TerminalHost
        # Raised when the emulator refused or failed a request. Callers
        # rescue it and fall back as for a host that cannot do the request.
        class Error < SFL::Error; end

        # @param cmd [Array<String>] the argv to run
        # @param cwd [String] the working directory of the new tab
        # @param title [String] the tab title
        # @param env [Hash{String => String}] extra environment for the command
        # @return [Boolean] true when a tab was opened, false when the host cannot open tabs
        # @raise [Error] when the emulator failed the request
        def launch_tab(cmd:, cwd:, title:, env: {})
          raise NotImplementedError, "#{self.class} must implement #launch_tab"
        end

        # @param path [String] an image file
        # @return [Boolean] true when shown, false when the host cannot show images
        # @raise [Error] when the emulator failed the request
        def show_image(path)
          raise NotImplementedError, "#{self.class} must implement #show_image"
        end
      end
    end
  end
end
