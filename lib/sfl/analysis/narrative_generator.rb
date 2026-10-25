# frozen_string_literal: true

module SFL
  module Analysis
    # Generates an LLM-written interpretive narrative from analysis data.
    # The Digest is the single input contract, built from an in-memory
    # Core::Types::AnalysisResult (Digest.from_result).
    #
    # This class does not depend on DSPy. Legacy's default SFLNarrator and its
    # multi-model Achilles/Tortoise/Genie variant are not ported here.
    # `narrator:` is a required keyword argument. The narrator, a RubyLLM chat
    # call, lives in lib/sfl/llm/narrators/narrative_generator.rb and is
    # injected by the CLI. All this class needs from a narrator is the duck contract:
    # `#call(digest_text) -> Hash` keyed by (a subset/superset of) SECTION_KEYS.
    class NarrativeGenerator
      SECTION_KEYS = %i[
        overview
        cast_and_roles
        interpersonal_dynamics
        conversational_arc
        data_quality
        takeaways
      ].freeze

      # @param narrator [#call] (digest_text) -> Hash of SECTION_KEYS.
      #   No default — every caller must inject one (DI-everywhere house
      #   convention; see this file's class comment for why legacy's
      #   DSPy-backed default isn't ported).
      def initialize(narrator:)
        @narrator = narrator
      end

      # @param digest [Digest]
      # @return [Core::Types::NarrativeReport]
      # @raise [NarrativeError] on narrator failure or missing sections
      # rescue clauses each mapping a distinct failure mode to NarrativeError; ported verbatim from legacy.
      def generate(digest)
        sections = @narrator.call(digest.to_text)
        Core::Types::NarrativeReport.new(
          source: digest.source,
          generated_at: Time.now,
          **sections.to_h.slice(*SECTION_KEYS)
        )
      rescue Dry::Struct::Error => e
        raise NarrativeError, "Narrative output missing or invalid sections: #{e.message}"
      rescue NarrativeError
        raise
      rescue => e
        raise NarrativeError, "Narrative generation failed: #{e.message}"
      end

      # Source-agnostic, string-keyed snapshot of an analysis, plus its
      # serialization to the exact text block the LLM receives.
      #
      # Two constructors: .from_result builds from an in-memory
      # Core::Types::AnalysisResult; .from_json builds from a report JSON
      # previously written by Formatters::JSONFormatter, so narration can
      # run on a saved report without re-running the analysis.
      # rubocop:disable Metrics/ClassLength -- one snapshot builder (from_result + its private row
      # helpers) plus one serializer (#to_text + its private helpers), ported verbatim from legacy.
      class Digest
        UNRELIABLE_THRESHOLD = 0.5

        # Must match Formatters::JSONFormatter::PREVIEW_LENGTH once that
        # lands (legacy's own comment on this constant) — kept as a plain
        # literal here since Formatters isn't built yet in this rebuild.
        PREVIEW_LENGTH = 200

        attr_reader :metadata, :speaker_profiles, :correlations, :insights, :turns, :key_moments

        # @param result [Core::Types::AnalysisResult]
        # @return [Digest]
        def self.from_result(result)
          new(
            metadata: deep_stringify(result.metadata.merge(annotation_coverage: coverage(result))),
            speaker_profiles: deep_stringify(profiles_hash(result.speaker_profiles)),
            correlations: deep_stringify(result.correlations),
            insights: result.insights,
            turns: turn_rows(result.turns),
            key_moments: deep_stringify(key_moment_rows(result.key_moments))
          )
        end

        # Turn-row keys a report JSON must carry for the digest to be built.
        REQUIRED_TURN_KEYS = %w[
          turn_id speaker preview avg_tenor avg_modality dominant_mood clause_count defaulted_count
        ].freeze
        OPTIONAL_TURN_KEYS = %w[tenor_shift semantic_coherence_score].freeze

        # Builds a digest from a report JSON written by Formatters::JSONFormatter,
        # so `narrate` can run on a saved report without re-running the analysis.
        # Accepts both report schemes: the conversation keys (conversation_id,
        # turn_count, speakers) and the document keys (document_key, section_count,
        # headings). Both come back under the conversation keys this class uses.
        #
        # @param parsed [Hash] JSON.parse of the report
        # @return [Digest]
        # @raise [NarrativeError] when the report has no turns array or a turn row is incomplete
        def self.from_json(parsed)
          turns = parsed["turns"]
          if turns.nil?
            raise NarrativeError,
              "Report JSON has no `turns` array — it predates narrative support. Re-run the analysis to regenerate it."
          end

          turns.each do |row|
            REQUIRED_TURN_KEYS.each do |key|
              raise NarrativeError, "Turn row missing required key: #{key}" unless row.key?(key)
            end
          end

          raw_metadata = parsed.fetch("metadata", {})
          new(
            metadata: canonicalize_metadata(raw_metadata),
            speaker_profiles: parsed.fetch(profiles_key(raw_metadata), {}),
            correlations: parsed.fetch("correlations", {}),
            insights: parsed.fetch("insights", []),
            turns: turns.map { |row| row.slice(*REQUIRED_TURN_KEYS, *OPTIONAL_TURN_KEYS) },
            key_moments: parsed["key_moments"] || []
          )
        end

        # Renames the document-report keys back to the conversation vocabulary.
        # Each key is substituted in place rather than deleted and re-added, so
        # the METADATA section of #to_text keeps the same order as from_result.
        def self.canonicalize_metadata(meta)
          key_map = {
            meta["id_label"] || "conversation_id" => "conversation_id",
            "#{(meta['unit_label'] || 'turn').downcase}_count" => "turn_count",
            (meta["actors_list_label"] || "speakers").downcase => "speakers",
          }
          meta.each_with_object({}) { |(key, value), renamed| renamed[key_map.fetch(key, key)] = value }
        end

        def self.profiles_key(meta)
          "#{(meta['actor_label'] || 'speaker').downcase}_profiles"
        end

        # independently-meaningful piece of the digest, ported verbatim from legacy.
        private_class_method def self.turn_rows(turns)
          turns.map do |t|
            {
              "turn_id" => t.turn_id,
              "speaker" => t.speaker,
              "preview" => t.message_text[0, PREVIEW_LENGTH],
              "avg_tenor" => t.avg_tenor,
              "avg_modality" => t.avg_modality,
              "dominant_mood" => t.dominant_mood,
              "tenor_shift" => t.tenor_shift,
              "clause_count" => t.clauses.size,
              "defaulted_count" => defaulted_count(t.clauses),
              "semantic_coherence_score" => t.semantic_coherence_score,
            }
          end
        end
        private_class_method def self.key_moment_rows(key_moments)
          key_moments.map do |km|
            {
              "type" => km.type,
              "turn_id" => km.turn_id,
              "magnitude" => km.magnitude,
              "description" => km.description,
            }
          end
        end

        def self.defaulted_count(clauses)
          clauses.count { |c| !Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(c.interpersonal.annotation_source) }
        end

        def self.defaulted_pct(clauses)
          return 0.0 if clauses.empty?

          (defaulted_count(clauses) * 100.0 / clauses.size).round(1)
        end

        def self.coverage(result)
          clauses = result.turns.flat_map(&:clauses)
          sources = clauses.map { |c| c.interpersonal.annotation_source }.tally
          {
            total_clauses: clauses.size,
            llm: sources.fetch("llm", 0),
            human: sources.fetch("human", 0),
            fallback: sources.fetch("fallback", 0),
            stub: sources.fetch("stub", 0),
            defaulted_pct: defaulted_pct(clauses),
          }
        end

        def self.profiles_hash(profiles)
          profiles.transform_values do |p|
            p.respond_to?(:to_h) ? p.to_h.except(:speaker_name) : p
          end
        end

        def self.deep_stringify(obj)
          case obj
          when Hash  then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
          when Array then obj.map { |v| deep_stringify(v) }
          else obj
          end
        end

        # attr_reader'd field, ported verbatim from legacy's own Digest#initialize.
        def initialize(metadata:, speaker_profiles:, correlations:, insights:, turns:, key_moments: [])
          @metadata = metadata
          @speaker_profiles = speaker_profiles
          @correlations = correlations
          @insights = insights
          @turns = turns
          @key_moments = key_moments
        end

        def source
          metadata["conversation_id"] || metadata["source_path"] || "unknown"
        end

        # The exact LLM input.
        # fixed-section heredoc plus an optional KEY MOMENTS append, ported verbatim from legacy.
        def to_text
          text = low_confidence_notice
          text += <<~TEXT
            == METADATA ==
            #{metadata.map { |k, v| "#{k}: #{v}" }.join("\n")}

            == SPEAKER PROFILES ==
            #{speaker_profiles.map { |name, p| "#{name}: #{p}" }.join("\n")}

            == PROCESS/STANCE CORRELATIONS ==
            #{correlations.map { |k, v| "#{k}: #{v}" }.join("\n")}

            == MACHINE INSIGHTS ==
            #{insights.join("\n")}

            == TURNS (in order) ==
            #{turns.map { |t| turn_line(t) }.join("\n")}
          TEXT

          if key_moments && !key_moments.empty?
            km_text = key_moments.map do |km|
              "[#{km['type']}] turn #{km['turn_id']} (magnitude: #{km['magnitude']}) — #{km['description']}"
            end.join("\n")
            text += "\n== KEY MOMENTS ==\n#{km_text}\n"
          end

          text
        end
        # Mirrors the markdown formatter's "Low Confidence" banner — a
        # small-sample analysis needs the same caveat carried into the
        # narrative's own text, not just buried as a metadata field.
        private def low_confidence_notice
          return "" unless metadata["low_confidence"]

          count = metadata["clause_count"]
          threshold = metadata["low_confidence_threshold"]
          "== LOW CONFIDENCE WARNING ==\n" \
            "This analysis is based on only #{count} clauses (minimum #{threshold} recommended). " \
            "Explicitly caveat the narrative as a small-sample, provisional analysis.\n\n"
        end

        # legacy; every field is an independently-meaningful piece of the LLM's per-turn input.
        private def turn_line(row)
          defaulted_pct =
            row["clause_count"].to_i.positive? ? row["defaulted_count"].to_f / row["clause_count"] : 0.0
          line = "turn #{row['turn_id']} [#{row['speaker']}] mood=#{row['dominant_mood']} " \
            "tenor=#{row['avg_tenor']} modality=#{row['avg_modality']} " \
            "shift=#{row['tenor_shift'].inspect} " \
            "clauses=#{row['clause_count']} defaulted=#{row['defaulted_count']}"
          line += " coherence=#{row['semantic_coherence_score']}" if row["semantic_coherence_score"]
          line += " UNRELIABLE (#{(defaulted_pct * 100).round}% fallback)" if defaulted_pct > UNRELIABLE_THRESHOLD
          "#{line}\n  preview: #{row['preview']}"
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
