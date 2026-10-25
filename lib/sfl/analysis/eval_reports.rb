# frozen_string_literal: true

require "json"

module SFL
  module Analysis
    # Renders one analyzer result Hash as Markdown and JSON text for the
    # eval:tenor_coherence, eval:process_mix and eval:gap_analysis rake tasks.
    # Pure: it formats the Hash it is given and reads and writes no files.
    #
    # Input:
    #   name    - :tenor_coherence, :process_mix or :gap_analysis
    #   result  - the Hash the matching analyzer returns:
    #               :tenor_coherence -> TenorCoherenceCorrelation#call
    #                 {coefficient:, p_value:, n:}
    #               :process_mix -> ProcessMixAnalyzer#call
    #                 {baseline: {type => share},
    #                  per_speaker: {speaker => {distribution:, deviation:, total_deviation:}}}
    #               :gap_analysis -> GapAnalyzer#call
    #                 {long_pause_threshold_seconds:, after_long_pause: {turns:, spikes:, rate:},
    #                  other: {turns:, spikes:, rate:}, p_value:, method:, reason:}
    #   sources - Array<String>, the report paths the result was computed from.
    #
    # Output: {markdown: String, json: String}. The JSON text is
    #   {"report": name, "sources": [...], "result": result}
    # and its "result" value equals the input result with string keys. A nil
    # coefficient, p-value, rate or method is written as "not computed" in the
    # Markdown and as null in the JSON.
    class EvalReports # rubocop:disable Metrics/ClassLength -- one renderer per report shape; splitting them would scatter the three layouts across files outside the brief
      NAMES = %i[tenor_coherence process_mix gap_analysis].freeze

      def self.render(name, result, sources:)
        new(name:, result:, sources:).render
      end

      def initialize(name:, result:, sources:)
        raise ArgumentError, "unknown eval report #{name.inspect}" unless NAMES.include?(name)

        @name = name
        @result = result
        @sources = sources
      end

      def render
        { markdown: markdown_text, json: json_text }
      end

      private def markdown_text
        lines = case @name
                when :tenor_coherence then tenor_coherence_markdown
                when :process_mix then process_mix_markdown
                else gap_analysis_markdown
        end
        "#{lines.join("\n")}\n"
      end

      private def json_text
        JSON.pretty_generate({ report: @name.to_s, sources: @sources, result: @result }) << "\n"
      end

      private def tenor_coherence_markdown
        n = @result.fetch(:n)
        lines = [
          "# Tenor and semantic coherence",
          "",
          "Spearman rank correlation (tie-corrected) between each turn's avg_tenor and its " \
            "semantic_coherence_score. A turn is used only when both values are present. The p-value is " \
            "two-sided, from t = r * sqrt((n - 2) / (1 - r^2)) with n - 2 degrees of freedom.",
          "",
          "| Quantity | Value |",
          "| --- | --- |",
          "| n (usable turns) | #{n} |",
          "| Coefficient (rho) | #{fmt(@result[:coefficient], 3)} |",
          "| p-value | #{fmt(@result[:p_value], 4, :g)} |",
          "",
        ]
        if @result[:coefficient].nil?
          lines << "The coefficient is not computed: n = #{n}, and at least 3 usable turns with non-constant " \
            "values are needed."
        end
        lines + sources_section
      end

      private def process_mix_markdown
        baseline = @result.fetch(:baseline)
        lines = [
          "# Process mix by speaker",
          "",
          "Baseline: the process-type share of all trusted clauses (annotation source llm or human). " \
            "Deviation: the speaker's share minus the baseline share. Total deviation: half the L1 distance " \
            "between the speaker's distribution and the baseline (total variation distance).",
          "",
        ]
        return lines + ["No trusted clauses; there is no baseline to compare.", ""] + sources_section if baseline.empty?

        lines += ["## Baseline", "", "| Process type | Share |", "| --- | --- |"]
        lines += baseline.map { |type, share| "| #{type} | #{fmt(share, 3)} |" }
        lines << ""
        @result.fetch(:per_speaker).each do |speaker, profile|
          lines += [
            "## #{speaker} (total deviation #{fmt(profile[:total_deviation], 3)})",
            "",
            "| Process type | Share | Deviation |",
            "| --- | --- | --- |",
          ]
          baseline.each_key do |type|
            lines << "| #{type} | #{fmt(profile[:distribution][type], 3)} | #{fmt(profile[:deviation][type], 3)} |"
          end
          lines << ""
        end
        lines + sources_section
      end

      private def gap_analysis_markdown
        lines = [
          "# Tenor spikes after long pauses",
          "",
          "Long pause: a gap between consecutive turns that is strictly greater than the conversation's " \
            "75th-percentile gap and at least #{@result.fetch(:long_pause_threshold_seconds)} seconds. " \
            "A turn is \"after a long pause\" when the gap before it is a long pause. The first turn of each " \
            "conversation counts as \"other\". Spikes come from TenorTracker#detect_significant_shifts.",
          "",
          "| Group | Turns | Spikes | Rate |",
          "| --- | --- | --- | --- |",
          gap_row("After long pause", @result.fetch(:after_long_pause)),
          gap_row("Other", @result.fetch(:other)),
          "",
          "| Quantity | Value |",
          "| --- | --- |",
          "| Threshold (floor, seconds) | #{@result.fetch(:long_pause_threshold_seconds)} |",
          "| p-value | #{fmt(@result[:p_value], 4, :g)} |",
          "| Method | #{@result[:method] || 'not computed'} |",
        ]
        lines << "" << "The test is not computed: #{@result[:reason]}." if @result[:reason]
        lines + sources_section
      end

      private def gap_row(label, group)
        "| #{label} | #{group.fetch(:turns)} | #{group.fetch(:spikes)} | #{fmt(group[:rate], 3)} |"
      end

      private def sources_section
        ["", "## Sources", ""] + @sources.map { |path| "- #{path}" } + [""]
      end

      # nil renders as "not computed". Floats use fixed decimals, or %g for p-values.
      private def fmt(value, digits, style = :f)
        return "not computed" if value.nil?
        return value.to_s unless value.is_a?(Numeric)

        (style == :g) ? format("%.#{digits}g", value) : format("%.#{digits}f", value)
      end
    end
  end
end
