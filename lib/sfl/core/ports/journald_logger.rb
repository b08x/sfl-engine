# frozen_string_literal: true

require "journald/logger"

module SFL
  module Core
    module Ports
      class JournaldLogger
        include Ports::Logger

        def initialize(progname: "sfl-engine", level: ::Journald::LOG_INFO, tags: {})
          @logger = ::Journald::Logger.new(progname, level, **tags)
        end

        def debug(message = nil, &block)
          message ||= block&.call
          logger.log_debug(message) if message
        end

        def info(message = nil, &block)
          message ||= block&.call
          logger.log_info(message) if message
        end

        def warn(message = nil, &block)
          message ||= block&.call
          logger.log_warning(message) if message
        end

        def error(message = nil, &block)
          message ||= block&.call
          logger.log_err(message) if message
        end

        def fatal(message = nil, &block)
          message ||= block&.call
          logger.log_crit(message) if message
        end

        attr_reader :logger
        private :logger
      end
    end
  end
end
