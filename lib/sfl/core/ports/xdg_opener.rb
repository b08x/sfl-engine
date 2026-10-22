# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Opener adapter that runs `xdg-open` as a detached child with its
      # output discarded, so it never writes into the TUI frame.
      class XdgOpener
        include Opener

        COMMAND = "xdg-open"

        # @param spawner [#call] (*argv, **opts) -> pid, Process.spawn by default
        # @param detacher [#call] pid -> Thread, Process.detach by default
        def initialize(spawner: Process.method(:spawn), detacher: Process.method(:detach))
          @spawner = spawner
          @detacher = detacher
        end

        def open(path)
          pid = @spawner.call(COMMAND, path.to_s, out: File::NULL, err: File::NULL)
          @detacher.call(pid)
          nil
        end
      end
    end
  end
end
