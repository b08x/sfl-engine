# frozen_string_literal: true

module SFL
  module Dashboard
    # Logger that writes each line to the Board's bounded log instead of
    # stderr, which the dashboard owns while it is drawn. Boot.logger puts it
    # in place of the stderr target. A warning carrying `status: 429` about a
    # retry counts as one rate-limit backoff.
    class RingLogger
      include Core::Ports::Logger

      RATE_LIMIT_STATUS = 429

      # @param board [Board]
      # @param level [Integer] minimum severity, Boot::LOG_LEVELS values
      def initialize(board, level: 1)
        @board = board
        @level = level
      end

      SEVERITIES = %i[debug info warn error fatal].freeze

      SEVERITIES.each_with_index do |severity, rank|
        define_method(severity) do |message = nil, **fields, &block|
          write(severity, message || block&.call, fields) if rank >= @level
          nil
        end
      end

      private def write(severity, text, fields)
        pairs = fields.except(:run_id).map { |key, value| "#{key}=#{value}" }
        line = ["[#{severity.upcase}]", text, *pairs].compact.join(" ")
        backoff = severity == :warn && fields[:status] == RATE_LIMIT_STATUS && text.to_s.include?("retrying")
        @board.update { |state| state.add_log(line, backoff:) }
      end
    end
  end
end
