# frozen_string_literal: true

require "dry/monads"

module SFL
  module TUI
    # Builds bubbletea commands that cannot raise.
    #
    # bubbletea-ruby runs a Proc command on a background thread and uses its
    # return value as the next message. If that Proc raises, the runner
    # swallows the exception after the backtrace has already been written over
    # the alt-screen frame — the app appears to hang with a corrupted display
    # and nothing in the log. So every command this codebase builds goes
    # through here: the block's Result is unwrapped on the command thread and
    # a Failure becomes a Messages::Failed, which `update` then turns into a
    # visible error state.
    module SafeCommand
      extend self

      include Dry::Monads[:result, :try]

      # @param source [Symbol] tag for the failure message
      # @param logger [#error, nil]
      # @yieldreturn [Dry::Monads::Result, Bubbletea::Message] a Success wraps
      #   the message to dispatch; a Failure carries operator-facing detail
      # @return [Proc] a command that always returns a Bubbletea::Message
      # Try(Exception, &), not the default Try(StandardError, &): a
      # NotImplementedError from an unfinished workspace hook is a ScriptError,
      # so the default would let it escape onto the command thread — precisely
      # the swallowed-background-exception failure this module exists to
      # prevent. Interrupt is re-raised so ctrl+c still reaches the runner.
      def wrap(source:, logger: nil, &)
        lambda do
          result = Try(Exception, &).to_result.bind { |value| value.is_a?(Dry::Monads::Result) ? value : Success(value) }

          case result
          in Dry::Monads::Success(message) then message
          in Dry::Monads::Failure(Interrupt => interrupt) then raise(interrupt)
          in Dry::Monads::Failure(failure)
            detail = failure.is_a?(Exception) ? "#{failure.class}: #{failure.message}" : failure.to_s
            logger&.error("tui command failed (#{source}): #{detail}")
            Messages::Failed.new(source, detail)
          end
        end
      end
    end
  end
end
