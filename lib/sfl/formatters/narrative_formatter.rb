# frozen_string_literal: true

module SFL
  module Formatters
    # Renders a Core::Types::NarrativeReport as markdown. Deterministic
    # assembly: the LLM wrote the prose, this class owns the skeleton.
    #
    # Pass `citation_check:` (result of CitationGroundingChecker#check) to
    # append a Hallucination Report section and coverage footer.
    class NarrativeFormatter < BaseFormatter
      SECTIONS = [
        ["Overview", :overview],
        ["Cast & Roles", :cast_and_roles],
        ["Interpersonal Dynamics", :interpersonal_dynamics],
        ["Conversational Arc", :conversational_arc],
        ["Data Quality", :data_quality],
        ["Takeaways", :takeaways],
      ].freeze

      def initialize(result, citation_check: nil)
        super(result)
        @citation_check = citation_check
      end

      def render
        body = SECTIONS.map do |title, key|
          "## #{title}\n\n#{result.public_send(key)}\n"
        end.join("\n")

        md = <<~MARKDOWN
          # Narrative Report: #{result.source}

          *Generated #{result.generated_at.iso8601} by sfl-engine narrative generation.*

          #{body}
        MARKDOWN

        md + hallucination_section + coverage_footer
      end

      private def hallucination_section
        return "" unless @citation_check

        ungrounded = @citation_check[:ungrounded]
        return "" if ungrounded.empty?

        lines = ungrounded.each_with_index.map do |item, i|
          "#{i + 1}. **UNGROUNDED**: \"#{item[:sentence]}\" — #{item[:reason]}"
        end

        "\n## Hallucination Report\n\nThe following claims could not be grounded in source clauses:\n\n" \
          "#{lines.join("\n")}\n"
      end

      private def coverage_footer
        return "" unless @citation_check

        check  = @citation_check
        total  = check[:grounded].size + check[:ungrounded].size
        n      = check[:grounded].size
        pct    = total.zero? ? 0.0 : (n.to_f / total * 100).round(1)
        "\n---\n\n*Citation coverage: #{n}/#{total} claims grounded (#{pct}%)*\n"
      end
    end
  end
end
