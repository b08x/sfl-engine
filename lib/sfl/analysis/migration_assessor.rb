# frozen_string_literal: true

module SFL
  module Analysis
    # Produces a migration action and human-readable reason for a KB
    # artifact from its content_type and quality_score.
    #
    # Decision matrix (checked in this order):
    #   :ai_generated               -> review    (verify against ground truth, reword before migrating)
    #   :draft/:code_snippet/:image -> review    (needs a human judgment call)
    #   quality < 0.35              -> archive   (too sparse/fallback-heavy to migrate)
    #   :technical_reference/:tutorial >= 0.65 -> keep
    #   quality >= 0.50             -> update    (good content, check before migrating)
    #   else                        -> archive
    #
    # Ported from legacy's MigrationAssessor verbatim.
    class MigrationAssessor
      GROUND_TRUTH_TYPES = %i[ai_generated].freeze
      REVIEW_TYPES        = %i[draft code_snippet image].freeze
      KEEP_TYPES          = %i[technical_reference tutorial].freeze
      KEEP_THRESHOLD      = 0.65
      UPDATE_THRESHOLD    = 0.50
      ARCHIVE_QUALITY     = 0.35

      # @param artifact_id [Integer]
      # @param title [String]
      # @param source_file [String]
      # @param content_type [Symbol]
      # @param quality_score [Float]
      # @return [Core::Types::MigrationManifestEntry]
      def assess(artifact_id:, title:, source_file:, content_type:, quality_score:)
        action, reason = recommend(content_type, quality_score)

        Core::Types::MigrationManifestEntry.new(
          artifact_id:, title:, source_file:,
          action:, reason:, quality_score:, content_type:
        )
      end

      # rubocop:disable Metrics/MethodLength -- one ordered decision matrix, ported verbatim from
      # legacy's own #recommend (see the class comment for the documented priority order); each
      # branch returns an independently-meaningful [action, reason] pair.
      private def recommend(content_type, quality_score)
        if GROUND_TRUTH_TYPES.include?(content_type)
          [:review, "AI-generated — verify against ground truth and reword before migrating"]
        elsif REVIEW_TYPES.include?(content_type)
          [:review, "#{content_type.to_s.tr('_', ' ')} — requires manual decision before migration"]
        elsif quality_score < ARCHIVE_QUALITY
          [:archive, "Quality score #{quality_score} below archive threshold (#{ARCHIVE_QUALITY}) — insufficient data"]
        elsif KEEP_TYPES.include?(content_type) && quality_score >= KEEP_THRESHOLD
          [:keep, "High-quality #{content_type.to_s.tr('_', ' ')} (score: #{quality_score}) — migrate as-is"]
        elsif quality_score >= UPDATE_THRESHOLD
          [:update, "Adequate quality (score: #{quality_score}) — review and update before migrating"]
        else
          [:archive, "Low quality score (#{quality_score}) for #{content_type.to_s.tr('_', ' ')} — archive candidate"]
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
