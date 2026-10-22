# frozen_string_literal: true

require "tty-command"

module SFL
  module Core
    module Ports
      # TerminalHost adapter for kitty (0.43.1), through `kitten @` remote
      # control at the instance's listen_on address. A new tab runs a
      # command with `launch --type=tab`; an image is shown with
      # `kitten icat --hold` in an overlay window above the TUI, so the
      # TUI's own screen is left alone and comes back on a key press.
      class KittyHost
        include TerminalHost

        KITTEN = "kitten"
        UNIX_PREFIX = "unix:"

        # The adapter is chosen only inside a kitty window whose remote
        # control address is reachable.
        # @param window_id [String, nil] KITTY_WINDOW_ID
        # @param listen_on [String, nil] KITTY_LISTEN_ON, e.g. "unix:/tmp/mykitty-4770"
        # @param socket_check [#call] path -> Boolean, File.socket? by default
        # @param runner [#run] passed to the adapter
        # @return [TerminalHost] a KittyHost, else a Null::TerminalHost
        def self.detect(window_id:, listen_on:, socket_check: File.method(:socket?), runner: nil)
          return Null::TerminalHost.new unless reachable?(window_id, listen_on, socket_check)

          runner ? new(listen_on:, runner:) : new(listen_on:)
        end

        # An abstract socket ("unix:@name") has no file to check; a tcp
        # address is taken as given.
        def self.reachable?(window_id, listen_on, socket_check)
          return false if window_id.to_s.strip.empty? || listen_on.to_s.strip.empty?
          return true unless listen_on.start_with?(UNIX_PREFIX)

          path = listen_on.delete_prefix(UNIX_PREFIX)
          path.start_with?("@") || socket_check.call(path)
        end

        # @param listen_on [String] the `--to` address
        # @param runner [#run] (*argv) -> result, raising on failure; TTY::Command by default
        def initialize(listen_on:, runner: TTY::Command.new(printer: :null))
          @listen_on = listen_on
          @runner = runner
        end

        def launch_tab(cmd:, cwd:, title:, env: {})
          env_args = env.flat_map { |name, value| ["--env", "#{name}=#{value}"] }
          remote("launch", "--type=tab", "--tab-title", title, "--cwd", cwd, "--hold", *env_args, "--", *cmd)
        end

        def show_image(path)
          remote("launch", "--type=overlay", "--title", "sfl image", "--", KITTEN, "icat", "--hold", "--", path.to_s)
        end

        private def remote(*)
          @runner.run(KITTEN, "@", "--to", @listen_on, *)
          true
        rescue TTY::Command::ExitError, SystemCallError => e
          raise TerminalHost::Error, "kitty remote control failed: #{e.message.lines.first.to_s.strip}"
        end
      end
    end
  end
end
