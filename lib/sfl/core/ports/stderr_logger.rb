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

        def initialize(level: ::Logger::INFO, run_id: nil)
          @run_id = run_id
          @logger = ::Logger.new($stderr)
          @logger.level = level
          @logger.formatter = proc do |severity, _datetime, _progname, msg|
            "[#{severity}] #{msg}\n"
          end
        end

        def debug(message = nil, **fields, &)
          log(:debug, message, fields, &)
        end

        def info(message = nil, **fields, &)
          log(:info, message, fields, &)
        end

        def warn(message = nil, **fields, &)
          log(:warn, message, fields, &)
        end

        def error(message = nil, **fields, &)
          log(:error, message, fields, &)
        end

        def fatal(message = nil, **fields, &)
          log(:fatal, message, fields, &)
        end

        # ::Logger takes one message, so fields become trailing key=value pairs.
        private def log(severity, message, fields, &block)
          @logger.public_send(severity) do
            text = message || block&.call
            fields = fields.merge(run_id: @run_id) if @run_id && !fields.key?(:run_id)
            fields.empty? ? text : [text, *fields.map { |key, value| "#{key}=#{value}" }].join(" ")
          end
        end
      end
    end
  end
end
