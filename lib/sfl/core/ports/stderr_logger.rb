# frozen_string_literal: true

require "logger"

module SFL
  module Core
    module Ports
      # A standard adapter that wraps Ruby's ::Logger to output to $stderr,
      # satisfying the Ports::Logger contract. Used by the CLI so normal
      # standard output can be purely artifacts/reports.
      class StderrLogger
        include Ports::Logger

        def initialize(level: ::Logger::INFO)
          @logger = ::Logger.new($stderr)
          @logger.level = level
          @logger.formatter = proc do |severity, _datetime, _progname, msg|
            "[#{severity}] #{msg}\n"
          end
        end

        def debug(message = nil, &)
          @logger.debug(message, &)
        end

        def info(message = nil, &)
          @logger.info(message, &)
        end

        def warn(message = nil, &)
          @logger.warn(message, &)
        end

        def error(message = nil, &)
          @logger.error(message, &)
        end

        def fatal(message = nil, &)
          @logger.fatal(message, &)
        end
      end
    end
  end
end
