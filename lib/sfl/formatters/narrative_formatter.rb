# frozen_string_literal: true

module SFL
  module Formatters
    # Renders a Core::Types::NarrativeReport as markdown. Deterministic
    # assembly: the LLM wrote the prose, this class owns the skeleton.
    #
    # Pass `grounding:` (a DigestGroundingChecker::Result) to append a Grounding
    # Check section and a weighted-precision footer.
    class NarrativeFormatter < BaseFormatter
      SECTIONS = [
        ["Overview", :overview],
        ["Cast & Roles", :cast_and_roles],
        ["Interpersonal Dynamics", :interpersonal_dynamics],
        ["Conversational Arc", :conversational_arc],
        ["Data Quality", :data_quality],
        ["Takeaways", :takeaways],
      ].freeze

      def initialize(result, grounding: nil)
        super(result)
        @grounding = grounding
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

        md + grounding_section + grounding_footer
      end

      private def grounding_section
        return "" unless @grounding

        if @grounding.findings.empty?
          return "\n## Grounding Check\n\nNo checkable claim failed against the digest.\n"
        end

        lines = @grounding.findings.each_with_index.map do |finding, i|
          band = finding.band || "unmarked"
          "#{i + 1}. **#{finding.check}** (#{band}, weight #{finding.weight}): \"#{finding.sentence}\" — #{finding.detail}"
        end

        "\n## Grounding Check\n\nClaims the digest does not support:\n\n#{lines.join("\n")}\n"
      end

      private def grounding_footer
        return "" unless @grounding

        precision = (@grounding.weighted_precision * 100).round(1)
        flagged = @grounding.findings.size
        "\n---\n\n*Weighted grounding precision: #{precision}% (#{@grounding.claim_count} claims checked, " \
          "#{flagged} flagged)*\n"
      end
    end
  end
end
