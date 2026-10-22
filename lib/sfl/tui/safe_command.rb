# frozen_string_literal: true

require "dry/monads"

module SFL
  module TUI
    # Builds commands that cannot raise, so an exception never ends the
    # event loop: the block's Result is unwrapped and a Failure, or any
    # exception other than Interrupt, becomes a Messages::Failed.
    module SafeCommand
      extend self

      include Dry::Monads[:result, :try]

      # @param source [Symbol] tag for the failure message
      # @param logger [Core::Ports::Logger, nil]
      # @yieldreturn [Dry::Monads::Result, Object] a Success wraps the message
      #   to dispatch; a Failure carries operator-facing detail
      # @return [Proc] a command that always returns a message
      # Try(Exception, &) rather than the StandardError default, so a
      # ScriptError such as NotImplementedError is caught as well.
      def wrap(source:, logger: nil, &)
        lambda do
          case outcome(&)
          in Dry::Monads::Success(message) then message
          in Dry::Monads::Failure(Interrupt => interrupt) then raise(interrupt)
          in Dry::Monads::Failure(failure) then failed(source, logger, failure)
          end
        end
      end

      private def outcome(&) = Try(Exception, &).to_result.bind { |value| value.is_a?(Dry::Monads::Result) ? value : Success(value) }

      private def failed(source, logger, failure)
        detail = failure.is_a?(Exception) ? "#{failure.class}: #{failure.message}" : failure.to_s
        logger&.error("tui command failed", source:, detail:)
        Messages::Failed.new(source, detail)
      end
    end
  end
end
