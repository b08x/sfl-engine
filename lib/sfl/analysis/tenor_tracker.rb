# frozen_string_literal: true

module SFL
  module Analysis
    # Tracks tenor (formality) evolution across conversation turns. Ported
    # faithfully from legacy's TenorTracker — the card's later "TenorShifts
    # F5 bug" bullet (a separate slice) fixes calculate_shifts' behavior;
    # this slice only relocates the current behavior into the new
    # namespace, unchanged.
    class TenorTracker
      attr_reader :turns, :threshold

      def initialize(turns, threshold: 0.15)
        @turns = turns
        @threshold = threshold
      end

      # Calculate tenor shifts between consecutive turns (mutates turns in-place).
      def calculate_shifts
        turns.each_with_index do |turn, idx|
          next unless idx.positive?

          shift = turn.avg_tenor - turns[idx - 1].avg_tenor
          turns[idx] = turn.new(tenor_shift: shift)
        end
      end

      # Find significant tenor shifts (above threshold).
      # @return [Array<Hash>] Shift metadata
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- ported verbatim from legacy
      def detect_significant_shifts
        calculate_shifts if turns.any? { |t| t.tenor_shift.nil? && t.turn_id > 1 }

        turns.select { |t| t.tenor_shift && t.tenor_shift.abs > threshold }.map do |turn|
          {
            turn_id: turn.turn_id,
            speaker: turn.speaker,
            from_tenor: turns[turn.turn_id - 2]&.avg_tenor,
            to_tenor: turn.avg_tenor,
            delta: turn.tenor_shift,
            direction: turn.tenor_shift.positive? ? "more formal" : "less formal",
          }
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end
