# frozen_string_literal: true

module SFL
  module Dashboard
    # Holds the current State for two threads: the run (progress and log
    # events) writes it, the dashboard's draw loop reads it.
    class Board
      # @param state [State]
      def initialize(state)
        @state = state
        @lock = Mutex.new
      end

      # @return [State]
      def state = @lock.synchronize { @state }

      # @yieldparam state [State]
      # @yieldreturn [State] the next state
      # @return [State]
      def update = @lock.synchronize { @state = yield(@state) }
    end
  end
end
