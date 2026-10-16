# frozen_string_literal: true

require "journald/logger"

module SFL
  module Core
    module Ports
      # Writes to systemd-journald with one structured field per keyword, plus
      # CODE_FILE / CODE_LINE / CODE_FUNC taken from the calling frame, so
      # `journalctl -o json` or `journalctl DOCUMENT_ID=doc-1` can filter on
      # state instead of parsing message text.
      class JournaldLogger
        include Ports::Logger

        # Syslog priorities, as journald PRIORITY.
        PRIORITIES = { debug: 7, info: 6, warn: 4, error: 3, fatal: 2 }.freeze
        RESERVED_FIELDS = %i[message priority].freeze

        def initialize(progname: "sfl-engine", level: ::Journald::LOG_INFO, tags: {})
          @logger = ::Journald::Logger.new(progname, level, **tags)
        end

        PRIORITIES.each_key do |severity|
          define_method(severity) do |message = nil, **fields, &block|
            emit(severity, message, fields, block, caller_locations(1, 1).first)
          end
        end

        attr_reader :logger
        private :logger

        private def emit(severity, message, fields, block, location)
          message ||= block&.call
          return unless message

          logger.send_message(
            fields.except(*RESERVED_FIELDS).merge(
              priority: PRIORITIES.fetch(severity), message:,
              code_file: location.path, code_line: location.lineno, code_func: location.label
            )
          )
        end
      end
    end
  end
end
