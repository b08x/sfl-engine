# frozen_string_literal: true

require "json"

module SFL
  module Formatters
    # Exports a KnowledgeBaseReport to JSON.
    class KBJsonFormatter < BaseFormatter
      def render
        JSON.pretty_generate(build_hash)
      end

      private def build_hash
        {
          metadata: result.metadata,
          content_type_distribution: result.content_type_distribution,
          quality_distribution: result.quality_distribution,
          staleness_flags: result.staleness_flags,
          migration_manifest: format_manifest,
          artifacts: format_artifacts,
        }
      end

      private def format_manifest
        result.migration_manifest.map do |entry|
          {
            artifact_id: entry.artifact_id,
            title: entry.title,
            source_file: entry.source_file,
            content_type: entry.content_type,
            quality_score: entry.quality_score,
            action: entry.action,
            reason: entry.reason,
          }
        end
      end
      # ported verbatim from legacy.
      private def format_artifacts
        result.artifacts.map do |artifact|
          {
            artifact_id: artifact.artifact_id,
            title: artifact.title,
            source_file: artifact.source_file,
            section_path: artifact.section_path,
            content_type: artifact.content_type,
            quality_score: artifact.quality_score,
            migration_action: artifact.migration_action,
            migration_reason: artifact.migration_reason,
            tags: artifact.tags,
            last_updated: artifact.last_updated&.iso8601,
            avg_tenor: artifact.avg_tenor,
            avg_modality: artifact.avg_modality,
            dominant_mood: artifact.dominant_mood,
            process_types: artifact.process_types,
            annotation_coverage: artifact.annotation_coverage,
          }
        end
      end
    end
  end
end
