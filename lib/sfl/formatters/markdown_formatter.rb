# frozen_string_literal: true

module SFL
  module Formatters
    # Exports conversation analysis to Markdown report.
    # rubocop:disable Metrics/ClassLength -- one report-assembly class plus its private section
    # renderers, ported verbatim from legacy.
    class MarkdownFormatter < BaseFormatter
      # rubocop:disable Metrics/AbcSize -- one fixed-section heredoc, ported verbatim from legacy.
      def render
        <<~MD
          # Conversation Analysis: #{result.metadata[:conversation_id]}

          **Generated**: #{result.metadata[:analyzed_at]}
          **#{unit_label}s**: #{result.metadata[:turn_count]} | **#{actors_list_label}**: #{result.metadata[:speakers]&.join(', ')}
          #{low_confidence_banner}
          #{data_quality_warning}
          ---

          ## Summary

          This analysis tracks **tenor evolution** (formality shifts), **field evolution** (topic/process changes), and **tenor ↔ field correlations** across the conversation.

          ---

          ## #{actor_label} Profiles

          #{speaker_profiles_table}

          ---

          ## Cohesion Metrics

          #{cohesion_table}

          ---

          ## Tenor ↔ Field Correlations

          #{correlations_table}

          ---

          ## Generated Insights

          #{insights_list}
          #{topic_modeling_section}
          #{key_moments_section}
          #{example_passages_section}
          #{reasoning_traces_section}
          ---

          ## Methodology

          **SFL Framework**: Two-Pass SFL Compiler (sfl-compiler)
          - **Pass 1**: Syntactic parsing (spaCy) + Ideational extraction (process types, participants)
          - **Pass 2**: Interpersonal annotation (DSPy.rb + LLM) → mood, modality, tenor, attitude

          **Tenor Scale**: 0.0 (informal/casual) ↔ 1.0 (formal/technical)
          **Modality Scale**: 0.0 (hedged/uncertain) ↔ 1.0 (certain/assertive)
        MD
      end
      # rubocop:enable Metrics/AbcSize

      # More prominent than #data_quality_warning: this is about sample
      # size, not annotation provenance — even a 100% LLM-annotated report
      # is unreliable in aggregate if it's only a few clauses.
      private def low_confidence_banner
        return "" unless result.metadata[:low_confidence]

        count = result.metadata[:clause_count]
        threshold = result.metadata[:low_confidence_threshold]
        <<~BANNER.chomp

          > ## 🚨 LOW CONFIDENCE: #{count} clauses (minimum #{threshold} recommended)
          > Aggregate modality/tenor scores below this sample size are statistically unreliable. Treat every finding in this report as provisional.
        BANNER
      end

      # Clauses whose interpersonal values came from the Pass 2 fallback or
      # a Pass-1-only stub all sit at the scale midpoint (0.5/0.5/declarative),
      # which silently drags every aggregate toward "mixed". Surface that.
      # chunk_artifact clauses (PDF chunk-boundary fragments) get their own
      # line — they're a distinct provenance from fallback/stub and are
      # already excluded from their turn's avg_tenor/avg_modality by
      # DocumentationAnalyzer, not just biasing them.
      private def data_quality_warning
        clauses = result.turns.flat_map(&:clauses)
        return "" if clauses.empty?

        lines = data_quality_lines(clauses)
        return "" if lines.empty?

        "#{lines.join("\n\n")}\n"
      end

      private def data_quality_lines(clauses)
        defaulted = clauses.count { |c| %w[fallback stub].include?(c.interpersonal.annotation_source) }
        chunk_artifacts = clauses.count { |c| c.interpersonal.annotation_source == "chunk_artifact" }
        return [] if defaulted.zero? && chunk_artifacts.zero?

        [data_quality_header, *data_quality_body_lines(defaulted, chunk_artifacts, clauses.size)].compact
      end

      private def data_quality_body_lines(defaulted, chunk_artifacts, total)
        [
          (data_quality_defaulted_line(defaulted, total) if defaulted.positive?),
          ("**#{chunk_artifacts} chunk-boundary artifacts excluded.**" if chunk_artifacts.positive?),
          (data_quality_all_defaulted_note if defaulted == total),
        ]
      end

      private def data_quality_header
        <<~HEADER.chomp

          ---

          ## ⚠️ Data Quality
        HEADER
      end

      private def data_quality_defaulted_line(defaulted, total)
        pct = (defaulted * 100.0 / total).round(1)
        "**#{defaulted} of #{total} clauses (#{pct}%)** carry fallback/stub interpersonal values " \
          "(tenor=0.5, modality=0.5, mood=declarative) instead of LLM annotations. " \
          "Tenor and modality averages are biased toward 0.5."
      end

      private def data_quality_all_defaulted_note
        "**Pass 2 did not run for any clause — the interpersonal values in this report are " \
          "placeholders, not findings.**"
      end

      private def actor_label
        result.metadata[:actor_label] || "Speaker"
      end

      private def unit_label
        result.metadata[:unit_label] || "Turn"
      end

      private def actors_list_label
        result.metadata[:actors_list_label] || "Speakers"
      end

      # rubocop:disable Metrics/AbcSize -- one flat profile-row table builder, ported verbatim from legacy.
      private def speaker_profiles_table
        return "_No speaker profiles available_" if result.speaker_profiles.empty?

        name_pad = [actor_label.length, 7].max
        header = "| #{actor_label.ljust(name_pad)} | Avg Tenor | Range | Variance | Avg Modality |\n"
        header += "|#{'-' * (name_pad + 2)}|-----------|-------|----------|--------------|\n"

        rows = result.speaker_profiles.map do |name, profile|
          "| #{name.to_s.ljust(name_pad)} | #{profile.avg_tenor.round(3)} (#{tenor_label(profile.avg_tenor)}) | " \
            "[#{profile.tenor_range.map { |v| v.round(2) }.join(', ')}] | " \
            "#{profile.tenor_variance.round(4)} | #{profile.avg_modality.round(3)} |"
        end

        header + rows.join("\n")
      end
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/AbcSize -- one flat cohesion-row table builder, ported verbatim from legacy.
      private def cohesion_table
        header = "| #{unit_label} | Speaker | Repetition | Conjunctions | Pronouns |\n"
        header += "|:-----|:---------|:-----------|:-------------|:---------|\n"

        rows = result.turns.filter_map do |turn|
          c = turn.cohesion
          next unless c

          "| #{turn.turn_id} | #{turn.speaker} | #{c.repetition_score.round(3)} | " \
            "#{c.conjunction_density.round(3)} | #{c.pronoun_density.round(3)} |"
        end

        return "_No cohesion metrics available_" if rows.empty?

        header + rows.join("\n")
      end
      # rubocop:enable Metrics/AbcSize

      private def correlations_table
        return "_No correlations available_" if result.correlations.empty?

        header = "| Process Type | Avg Tenor | Avg Modality | Count |\n"
        header += "|--------------|-----------|--------------|-------|\n"

        rows = result.correlations.filter_map do |process_type, data|
          next unless data.is_a?(Hash) && data[:count]

          "| #{process_type} | #{data[:avg_tenor].round(3)} | #{data[:avg_modality].round(3)} | #{data[:count]} |"
        end

        header + rows.join("\n")
      end

      private def insights_list
        return "_No insights generated_" if result.insights.empty?

        result.insights.map.with_index { |insight, i| "#{i + 1}. #{insight}" }.join("\n\n")
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one flat topic-list plus optional topic-evolution list, ported verbatim from legacy.
      private def topic_modeling_section
        return "" unless result.topic_labels&.any?

        section = ["", "### 🏷️ Topic Modeling", ""]
        section << "**#{result.topic_labels.size} topics identified**\n"

        result.topic_labels.each do |topic_id, words|
          top_words = words.first(5).join(", ")
          section << "- **Topic #{topic_id}**: #{top_words}"
        end

        if result.topic_evolution&.any?
          section << ""
          section << "**Topic Evolution:**"
          result.topic_evolution.each do |evolution|
            topic_words = result.topic_labels[evolution[:dominant_topic]]&.first(3)&.join(", ") ||
              "topic #{evolution[:dominant_topic]}"
            section << "- #{unit_label} #{evolution[:turn_id]}: #{topic_words}"
          end
        end

        section.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private def key_moments_section
        return "" if result.key_moments.empty?

        section = ["", "### ⚡ Key Moments", ""]
        result.key_moments.each do |moment|
          section << "- **#{unit_label} #{moment.turn_id}** (#{moment.type.tr('_', ' ')}): #{moment.description}"
        end
        section.join("\n")
      end

      # rubocop:disable Metrics/AbcSize -- one flat passage-block list builder, ported verbatim from legacy.
      private def example_passages_section
        return "" if result.example_passages.empty?

        section = ["", "### 📖 Example Passages", ""]
        result.example_passages.each do |passage|
          section << "#### #{passage.label} (score: #{passage.value.round(3)})"
          section << "> \"#{passage.text.tr("\n", ' ').strip}\""
          section << ""
          section << "*— #{passage.speaker}. #{passage.reason}.*"
          section << ""
        end
        section.join("\n")
      end
      # rubocop:enable Metrics/AbcSize

      # Clauses with reasoning_trace: nil (fallback/stub annotation_source)
      # render nothing here — same "fallback values aren't presented as
      # findings" principle as #data_quality_warning.
      private def reasoning_traces_section
        traced = result.turns.flat_map(&:clauses).select { |c| c.interpersonal.reasoning_trace }
        return "" if traced.empty?

        section = ["", "### 🔍 Reasoning Traces", ""]
        traced.each { |clause| section.concat(reasoning_trace_block(clause)) }
        section.join("\n")
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat details-block builder,
      # ported verbatim from legacy.
      private def reasoning_trace_block(clause)
        trace = clause.interpersonal.reasoning_trace
        block = [
          "> \"#{clause.text.tr("\n", ' ').strip}\"",
          "",
          "<details>",
          "<summary>Reasoning: #{trace.inference_rule} (confidence #{trace.confidence.round(2)})</summary>",
          "",
        ]
        block.concat(premises_table(trace.premises)) if trace.premises.any?
        block << "Derivation: `#{trace.derivation_hash}`"
        block << "</details>"
        block << ""
        block
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private def premises_table(premises)
        rows = premises.map do |p|
          "| #{p.source} | #{p.type} | #{p.value} | #{p.weight.nil? ? '—' : p.weight} |"
        end
        ["| Premise | Type | Value | Weight |", "|---|---|---|---|", *rows, ""]
      end

      private def tenor_label(tenor)
        case tenor
        when 0.0..0.3 then "casual"
        when 0.3..0.6 then "mixed"
        when 0.6..1.0 then "formal"
        else "unknown"
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
