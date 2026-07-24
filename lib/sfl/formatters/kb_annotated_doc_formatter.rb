# frozen_string_literal: true

module SFL
  module Formatters
    # Renders one KnowledgeArtifact's clauses back into the shape of a
    # section of the original document, each clause tagged inline with its
    # Pass 1 (process type) and Pass 2 (mood/tenor/modality) annotations —
    # the "annotated version of the original doc" the migration report's
    # artifact-level aggregates don't provide on their own.
    #
    # Renders a single section (heading + metadata + tagged clauses), not a
    # full standalone document: a source file can produce more than one
    # artifact (multiple headings, or a text pass and an image pass), so
    # KBAnnotatedDocWriter — not this class — owns the document-level
    # title/source framing and concatenates one or more sections into it.
    class KBAnnotatedDocFormatter < BaseFormatter
      def render
        "#{<<~MD.rstrip}\n"
          #{heading}

          **Content type**: #{result.content_type} | **Quality**: #{result.quality_score.round(2)} | **Action**: #{result.migration_action}
          #{data_quality_line}
          #{annotated_body}
        MD
      end

      private def heading
        "## #{result.section_path || "Artifact #{result.artifact_id}"}"
      end

      private def data_quality_line
        non_llm = result.clauses.count { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
        return "" if non_llm.zero?

        "\n> ⚠️ #{non_llm} of #{result.clauses.size} clauses carry fallback/stub annotations " \
          "(marked ⚠️ below) — treat their tags as estimates.\n"
      end

      private def annotated_body
        return "_No clauses extracted._" if result.clauses.empty?

        result.clauses.map { |clause| annotate_clause(clause) }.join("\n\n")
      end

      private def annotate_clause(clause)
        tag = "`[#{clause.ideational.process_type} · #{clause.interpersonal.mood} · " \
          "tenor=#{clause.interpersonal.tenor.round(2)} · " \
          "modality=#{clause.interpersonal.modality_weight.round(2)}]`"
        unless Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(clause.interpersonal.annotation_source)
          tag = "⚠️ #{tag}"
        end

        "#{clause.text} #{tag}"
      end
    end
  end
end
