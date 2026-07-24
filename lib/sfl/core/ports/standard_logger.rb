# frozen_string_literal: true

require "logger"

module SFL
  module Core
    module Ports
      # Default production Logger adapter: a thin wrapper around Ruby's
      # stdlib ::Logger, writing to $stdout by default. 12-factor: the
      # process emits a log stream and lets the environment decide where
      # it goes, rather than binding to a specific backend (systemd
      # journald, as the legacy Journald::Logger did) — this is also what
      # makes the Docker-based sidecar and a bare `python3` invocation
      # equally easy to observe, since neither needs a host journal.
      #
      # `progname` tags every line with the emitting component (e.g.
      # "sfl.core.pass_one.engine"), mirroring the legacy convention of
      # one named Journald::Logger per class, without hardcoding a
      # per-class instantiation into every constructor.
      class StandardLogger
        include Ports::Logger

        def initialize(io: $stdout, level: ::Logger::INFO, progname: nil)
          @logger = ::Logger.new(io)
          @logger.level = level
          @logger.progname = progname
          @logger.formatter = method(:format_line)
        end

        def debug(message = nil, &) = logger.debug(message, &)
        def info(message = nil, &) = logger.info(message, &)
        def warn(message = nil, &) = logger.warn(message, &)
        def error(message = nil, &) = logger.error(message, &)
        def fatal(message = nil, &) = logger.fatal(message, &)

        attr_reader :logger
        private :logger

        private def format_line(severity, datetime, progname, msg)
          tag = progname ? "#{progname}: " : ""
          "#{datetime.utc.iso8601(3)} #{severity.ljust(5)} #{tag}#{msg}\n"
        end
      end
    end
  end
end
