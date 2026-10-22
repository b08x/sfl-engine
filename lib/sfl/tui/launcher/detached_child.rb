# frozen_string_literal: true

require "fileutils"

module SFL
  module TUI
    module Launcher
      # Starts a command as a detached child in its own process group, with
      # stdin closed and stdout and stderr appended to a log file, so it
      # survives the TUI and never writes into its frame. Its stderr is not
      # a terminal, so an ingest draws no dashboard.
      class DetachedChild
        # @param log_dir [String] expanded against the TUI's working directory
        # @param cwd [String] the child's working directory
        # @param spawner [#call] (env, *argv, **opts) -> pid, Process.spawn by default
        # @param detacher [#call] pid -> Thread, Process.detach by default
        # @param mkdir [#call] dir -> void
        def initialize(log_dir:, cwd:, spawner: Process.method(:spawn), detacher: Process.method(:detach),
          mkdir: FileUtils.method(:mkdir_p)
        )
          @log_dir = File.expand_path(log_dir)
          @cwd = cwd
          @spawner = spawner
          @detacher = detacher
          @mkdir = mkdir
        end

        # @param argv [Array<String>]
        # @param env [Hash{String => String}] added to the inherited environment
        # @param name [String] the log file's base name
        # @return [String] the log file path
        def call(argv, env:, name:)
          @mkdir.call(@log_dir)
          log = File.join(@log_dir, "#{name}.log")
          pid = @spawner.call(env, *argv, chdir: @cwd, in: File::NULL, out: [log, "a"], err: %i[child out], pgroup: true)
          @detacher.call(pid)
          log
        end
      end
    end
  end
end
