# frozen_string_literal: true

module SFL
  module Analysis
    # Produces a 0-1 quality score for a KB artifact from four signals:
    #
    #   annotation_source (0.40 weight) - llm/human=1.0, fallback=0.4, stub/chunk_artifact=0.1/0.15
    #   avg_modality       (0.30 weight) - certainty of claims in the text
    #   substance          (0.20 weight) - clause count as a proxy for content depth
    #   freshness          (0.10 weight) - age relative to STALENESS_CUTOFF_MONTHS
    #
    # Weights reflect that annotation reliability and content certainty
    # matter most for KB decisions, while freshness is a weak signal
    # (stale but high-modality reference content is still worth keeping).
    # Ported from legacy's QualityScorer verbatim.
    class QualityScorer
      STALENESS_CUTOFF_MONTHS = 18
      SUBSTANCE_CEILING       = 20 # clauses; above this gives score 1.0

      SOURCE_WEIGHTS = {
        "llm" => 1.0,
        "human" => 1.0,
        "fallback" => 0.4,
        "stub" => 0.1,
        "chunk_artifact" => 0.15,
      }.freeze

      # @param clauses [Array<Core::Types::AnnotatedClause>]
      # @param last_updated [Time, nil]
      # @return [Float] 0.0..1.0, rounded to 3 decimal places
      def score(clauses:, last_updated: nil)
        return 0.0 if clauses.empty?

        src       = source_score(clauses)
        modality  = modality_score(clauses)
        substance = substance_score(clauses)
        freshness = freshness_score(last_updated)

        raw = (src * 0.40) + (modality * 0.30) + (substance * 0.20) + (freshness * 0.10)
        raw.round(3).clamp(0.0, 1.0)
      end

      private def source_score(clauses)
        weights = clauses.map { |c| SOURCE_WEIGHTS.fetch(c.interpersonal.annotation_source, 0.3) }
        weights.sum / weights.size.to_f
      end

      private def modality_score(clauses)
        vals = clauses.map { |c| c.interpersonal.modality_weight }
        vals.sum / vals.size.to_f
      end

      private def substance_score(clauses)
        [clauses.size.to_f / SUBSTANCE_CEILING, 1.0].min
      end

      private def freshness_score(last_updated)
        return 0.5 unless last_updated # unknown age -> neutral

        months_old = (Time.now - last_updated) / (60 * 60 * 24 * 30.0)
        [1.0 - (months_old / STALENESS_CUTOFF_MONTHS), 0.0].max
      end
    end
  end
end
