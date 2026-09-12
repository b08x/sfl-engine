# frozen_string_literal: true

module SFL
  module Formatters
    # Exports a KnowledgeBaseReport to a Markdown migration report.
    class KBMarkdownFormatter < BaseFormatter
      ACTION_EMOJI = {
        keep: "✅",
        update: "🔄",
        archive: "📦",
        review: "🔍",
        merge_candidate: "🔀",
      }.freeze

      def render
        <<~MD
          # Knowledge Base Migration Report

          **Generated**: #{result.metadata[:analyzed_at]}
          **Artifacts**: #{result.metadata[:artifact_count]} | **Files**: #{result.metadata[:file_count]}
          #{images_line}
          #{data_quality_warning}
          ---

          ## Executive Summary

          #{quality_distribution_table}

          ---

          ## Migration Manifest

          #{migration_manifest_table}

          ---

          ## Content Type Breakdown

          #{content_type_breakdown}
          #{staleness_section}
          ---

          ## Methodology

          **SFL Framework**: Two-Pass SFL Engine (sfl-engine)
          - **Pass 1**: Syntactic parsing (spaCy) + Ideational extraction
          - **Pass 2**: Interpersonal annotation (DSPy.rb + LLM) → mood, modality, tenor
          - **Quality scoring**: annotation source (40%) + modality (30%) + substance (20%) + freshness (10%)
        MD
      end

      private def images_line
        result.metadata[:images_analyzed] ? "**Images analyzed**: yes\n" : ""
      end

      private def data_quality_warning
        clauses = result.artifacts.flat_map(&:clauses)
        return "" if clauses.empty?

        non_llm = clauses.count { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
        return "" if non_llm.zero?

        pct = (non_llm * 100.0 / clauses.size).round(1)
        "\n> ⚠️ **Data Quality**: #{non_llm} of #{clauses.size} clauses (#{pct}%) " \
          "carry fallback/stub annotations — quality scores for those artifacts are estimates.\n"
      end

      # plus an action-count loop, ported verbatim from legacy.
      private def quality_distribution_table
        dist = result.quality_distribution
        counts = result.migration_manifest.map(&:action).tally

        rows = [
          "| Metric | Value |",
          "|--------|-------|",
          "| Total artifacts | #{result.metadata[:artifact_count]} |",
          "| High quality (≥ 0.65) | #{dist[:high] || 0} |",
          "| Medium quality (0.35–0.65) | #{dist[:medium] || 0} |",
          "| Low quality (< 0.35) | #{dist[:low] || 0} |",
          "| Stale (> 18 months) | #{result.staleness_flags.size} |",
          "",
          "| Migration Action | Count |",
          "|-----------------|-------|",
        ]

        ACTION_EMOJI.each_key do |action|
          rows << "| #{ACTION_EMOJI[action]} #{action.to_s.tr('_', ' ').capitalize} | #{counts.fetch(action, 0)} |"
        end

        rows.join("\n")
      end
      private def migration_manifest_table
        return "_No artifacts to migrate._" if result.migration_manifest.empty?

        header = "| # | Title | File | Type | Quality | Action | Reason |\n"
        header += "|---|-------|------|------|---------|--------|--------|\n"

        rows = result.migration_manifest.each_with_index.map do |entry, i|
          emoji = ACTION_EMOJI.fetch(entry.action, "")
          reason = (entry.reason.length > 60) ? "#{entry.reason[0, 60]}…" : entry.reason
          "| #{i + 1} | #{truncate(entry.title, 30)} | `#{File.basename(entry.source_file)}` | " \
            "#{entry.content_type} | #{entry.quality_score.round(2)} | #{emoji} #{entry.action} | #{reason} |"
        end

        header + rows.join("\n")
      end
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, -- one flat breakdown-by-content-type loop, ported verbatim from legacy.
      private def content_type_breakdown
        dist = result.content_type_distribution
        return "_No content type data._" if dist.empty?

        artifact_index = result.artifacts.group_by(&:content_type)
        sections = []

        dist.sort_by { |_, count| -count }.each do |type, count|
          sections << "### #{type.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')} (#{count})"
          (artifact_index[type] || []).first(5).each do |a|
            sections << "- **#{a.title}** — score: #{a.quality_score.round(2)}, " \
              "action: #{ACTION_EMOJI.fetch(a.migration_action, '')} #{a.migration_action}"
          end
          sections << "_…and #{count - 5} more_" if count > 5
          sections << ""
        end

        sections.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      private def staleness_section
        return "" if result.staleness_flags.empty?

        artifact_index = result.artifacts.to_h { |a| [a.artifact_id, a] }
        lines = ["", "---", "", "## ⏰ Staleness Flags", "", "_Content last updated more than 18 months ago:_", ""]

        result.staleness_flags.each do |flag|
          artifact = artifact_index[flag[:artifact_id]]
          next unless artifact

          date_str = flag[:last_updated]&.strftime("%Y-%m-%d") || "unknown"
          lines << "- **#{artifact.title}** (`#{File.basename(artifact.source_file)}`) — last updated: #{date_str}"
        end

        "#{lines.join("\n")}\n"
      end
      private def truncate(str, max)
        (str.length > max) ? "#{str[0, max]}…" : str
      end
    end
  end
end
