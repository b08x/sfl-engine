# frozen_string_literal: true

module SFL
  module LLM
    module Narrators
      # Splits a narrator's headed text into one body per section key. The
      # narrator asks for "## Heading" lines; text before the first heading is
      # discarded. Bold headings ("**Heading:**") are accepted too.
      module SectionParser
        # A required section is absent or has an empty body. Subclasses
        # Analysis::NarrativeError so the analysis layer passes it through.
        class MissingSectionsError < Analysis::NarrativeError; end

        # Section key => [heading the model writes, intent carried over from
        # the DSPy output fields (V1/V2 field descriptions)].
        SECTIONS = {
          overview: ["Overview", "What this conversation is: topic, participants, setting"],
          cast_and_roles: ["Cast and roles", "Each speaker's role as the grammar reveals it"],
          interpersonal_dynamics: ["Interpersonal dynamics", "Tenor/modality patterns and shifts between speakers"],
          conversational_arc: ["Conversational arc", "Phases, pivots, and how the interaction resolves"],
          data_quality: ["Data quality", "Annotation coverage caveats; which turns are unmeasured"],
          takeaways: ["Takeaways", "Three to five grounded conclusions"],
        }.freeze

        # Matches a heading line: "## Heading", "### Heading", or "**Heading**".
        HEADING_PATTERN = /\A\s*(?:\#{1,6}\s+|\*\*)\**\s*([A-Za-z][A-Za-z _]*?)[\s:*]*\z/
        HEADING_KEYS = SECTIONS.keys.to_h { |key| [key.to_s, key] }.freeze

        # @param text [String] the narrator's response text
        # @return [Hash] symbol-keyed, one String per SECTIONS key
        # @raise [MissingSectionsError] when a section is absent or empty
        module_function def call(text)
          found = Hash.new { |hash, key| hash[key] = +"" }
          current = nil
          text.to_s.each_line do |line|
            key = heading_key(line)
            if key
              current = key
            elsif current
              found[current] << line
            end
          end
          sections = SECTIONS.keys.to_h { |key| [key, found.fetch(key, "").strip] }
          missing = sections.select { |_key, body| body.empty? }.keys
          raise MissingSectionsError, "narrator response missing sections #{missing.join(', ')} (content_chars #{text.to_s.length})" if missing.any?

          sections
        end

        # @return [Symbol, nil] the section key the line heads, or nil
        module_function def heading_key(line)
          match = HEADING_PATTERN.match(line)
          return nil unless match

          HEADING_KEYS[match[1].downcase.gsub(/[^a-z]+/, "_").delete_prefix("_").delete_suffix("_")]
        end
      end
    end
  end
end
