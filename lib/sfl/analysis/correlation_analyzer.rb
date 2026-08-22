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
      # Only clauses with a trusted (llm/human) annotation_source contribute to
      # the averages: a fallback clause sits at the 0.5 midpoint by
      # construction, so including them turned every correlation row into
      # "0.5 / 0.5" and presented it as a measurement. `count` still reports
      # every clause in the group (that count is Pass 1 data and is real);
      # `annotated_count` says how many of them the averages actually rest on,
      # and a group with none reports nil, not a fabricated midpoint.
      #
      # @return [Hash{String => Hash}] {process_type =>
      #   {count:, annotated_count:, avg_tenor:, avg_modality:}}
      # rubocop:disable Metrics/AbcSize -- one group_by/transform_values pass ported verbatim
      # from legacy; splitting the tenor/modality extraction into its own method would only
      # relocate this, not shorten it.
      def correlate_process_tenor
        all_clauses = turns.flat_map(&:clauses)

        all_clauses.group_by { |c| c.ideational.process_type }.transform_values { |clauses| row_for(clauses) }
      end

      private def row_for(clauses)
        annotated = clauses.select { |c| annotated?(c) }

        {
          count: clauses.count,
          annotated_count: annotated.count,
          avg_tenor: annotated.empty? ? nil : mean(annotated.map { |c| c.interpersonal.tenor }),
          avg_modality: annotated.empty? ? nil : mean(annotated.map { |c| c.interpersonal.modality_weight }),
        }
      end

      private def annotated?(clause)
        Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(clause.interpersonal.annotation_source)
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
