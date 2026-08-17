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

        def debug(message = nil, &block)
          @logger.debug(message, &block)
        end

        def info(message = nil, &block)
          @logger.info(message, &block)
        end

        def warn(message = nil, &block)
          @logger.warn(message, &block)
        end

        def error(message = nil, &block)
          @logger.error(message, &block)
        end

        def fatal(message = nil, &block)
          @logger.fatal(message, &block)
        end
      end
    end
  end
end
