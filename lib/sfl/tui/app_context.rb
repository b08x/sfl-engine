# frozen_string_literal: true

module SFL
  module TUI
    # What App.build resolves once at startup: the Boot result, the logger
    # and the collaborators commands use.
    #
    # The logger is never a StderrLogger: a write to stderr lands inside the
    # full-screen frame.
    AppContext = Data.define(:boot, :logger, :services)
  end
end
