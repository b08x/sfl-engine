# frozen_string_literal: true

module SFL
  module TUI
    # Runs Program until it asks to quit: draw, read one message, update,
    # run the returned commands, repeat. Commands run on this thread, after
    # a draw, and each returns the next message.
    class EventLoop
      # @param services [Services]
      # @param draw [#call] state -> void, renders one frame
      # @param next_message [#call] -> Messages::Key or nil when no key arrived
      def initialize(services:, draw:, next_message:)
        @services = services
        @draw = draw
        @next_message = next_message
      end

      # @param state [Program::State]
      # @return [Program::State] the final state
      def run(state = Program.initial)
        state = drain(state, Program.init(@services))
        until state.quit
          @draw.call(state)
          message = @next_message.call
          next unless message

          state, command = Program.update(state, message, @services)
          state = drain(state, [command].compact)
        end
        state
      end

      private def drain(state, commands)
        until commands.empty?
          @draw.call(state)
          state, command = Program.update(state, commands.shift.call, @services)
          commands << command if command
        end
        state
      end
    end
  end
end
