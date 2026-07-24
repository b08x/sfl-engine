# frozen_string_literal: true

module SFL
  module Analysis
    # Analyzes correlations between field (process types) and tenor.
    # Ported faithfully from legacy's CorrelationAnalyzer.
    class CorrelationAnalyzer
      include Aggregations

      attr_reader :turns

      def initialize(turns)
        @turns = turns
      end

      # Correlate process types with tenor/modality.
      # @return [Hash{String => Hash}] {process_type => {count:, avg_tenor:, avg_modality:}}
      # rubocop:disable Metrics/AbcSize -- one group_by/transform_values pass ported verbatim
      # from legacy; splitting the tenor/modality extraction into its own method would only
      # relocate this, not shorten it.
      def correlate_process_tenor
        all_clauses = turns.flat_map(&:clauses)

        all_clauses.group_by { |c| c.ideational.process_type }.transform_values do |clauses|
          tenors = clauses.map { |c| c.interpersonal.tenor }
          modalities = clauses.map { |c| c.interpersonal.modality_weight }

          {
            count: clauses.count,
            avg_tenor: mean(tenors),
            avg_modality: mean(modalities),
          }
        end
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
