# frozen_string_literal: true

module SFL
  module Analysis
    # Tracks tenor (formality) evolution across conversation turns.
    #
    # F5 fix: #calculate_shifts is now a pure function — it returns a new
    # Array<Core::Types::ConversationTurn> instead of mutating @turns in
    # place, and #detect_significant_shifts looks up each turn's
    # predecessor by array adjacency (via #each_cons, matching
    # Engine#detect_key_moments's own idiom) rather than by arithmetic on
    # turn_id, which silently broke whenever turn_id didn't line up with
    # array position (filtered/reordered/gapped turns).
    class TenorTracker
      attr_reader :turns, :threshold

      def initialize(turns, threshold: 0.15)
        @turns = turns
        @threshold = threshold
      end

      # Calculate tenor shifts between consecutive turns.
      # @return [Array<Core::Types::ConversationTurn>] a new array; turns are
      #   not mutated in place. The first turn keeps whatever tenor_shift it
      #   already had (typically nil — no predecessor to diff against).
      def calculate_shifts
        return [] if turns.empty?

        turns.each_cons(2).with_object([turns.first]) do |(prev, curr), acc|
          acc << curr.new(tenor_shift: curr.avg_tenor - prev.avg_tenor)
        end
      end

      # Find significant tenor shifts (above threshold).
      # @return [Array<Hash>] Shift metadata
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength -- ported verbatim from legacy
      def detect_significant_shifts
        current = (turns.any? { |t| t.tenor_shift.nil? && t.turn_id > 1 }) ? calculate_shifts : turns

        current.each_cons(2).filter_map do |prev, curr|
          next unless curr.tenor_shift && curr.tenor_shift.abs > threshold

          {
            turn_id: curr.turn_id,
            speaker: curr.speaker,
            from_tenor: prev.avg_tenor,
            to_tenor: curr.avg_tenor,
            delta: curr.tenor_shift,
            direction: curr.tenor_shift.positive? ? "more formal" : "less formal",
          }
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    end
  end
end
