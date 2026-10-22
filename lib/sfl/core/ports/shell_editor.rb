# frozen_string_literal: true

require "shellwords"
require "tempfile"

module SFL
  module Core
    module Ports
      # Editor adapter that writes the text to a temp file, runs the editor
      # command on it and reads the file back.
      class ShellEditor
        include Editor

        class Error < SFL::Error; end

        # @param command [String] editor command line, e.g. "nvim" or "code -w"
        # @param suspend [#call] wraps the editor run; the TUI passes one that
        #   leaves raw mode and the alternate screen for the duration
        # @param runner [#call] (*argv) -> Boolean, Kernel#system by default
        def initialize(command:, suspend: -> (&block) { block.call }, runner: -> (*argv) { system(*argv) })
          @command = command
          @suspend = suspend
          @runner = runner
        end

        def edit(text)
          Tempfile.create(["sfl-edit", ".txt"]) do |file|
            file.write(text)
            file.close
            ok = @suspend.call { @runner.call(*Shellwords.split(@command), file.path) }
            raise Error, "editor exited with an error: #{@command}" unless ok

            File.read(file.path)
          end
        end
      end
    end
  end
end
