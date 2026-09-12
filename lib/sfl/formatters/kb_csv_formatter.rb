# frozen_string_literal: true

require "csv"

module SFL
  module Formatters
    # Exports a KnowledgeBaseReport to CSV — one row per artifact.
    class KBCsvFormatter < BaseFormatter
      HEADERS = %w[
        artifact_id
        title
        source_file
        section_path
        content_type
        quality_score
        migration_action
        tags
        last_updated
        llm_clause_count
        fallback_clause_count
      ].freeze

      def render
        CSV.generate do |csv|
          csv << HEADERS
          result.artifacts.each { |a| csv << artifact_to_row(a) }
        end
      end

      # ported verbatim from legacy.
      private def artifact_to_row(artifact)
        cov = artifact.annotation_coverage
        [
          artifact.artifact_id,
          artifact.title,
          artifact.source_file,
          artifact.section_path,
          artifact.content_type,
          artifact.quality_score.round(3),
          artifact.migration_action,
          artifact.tags.join("; "),
          artifact.last_updated&.strftime("%Y-%m-%d"),
          cov[:llm] || 0,
          cov[:fallback].to_i + cov[:stub].to_i,
        ]
      end
    end
  end
end
