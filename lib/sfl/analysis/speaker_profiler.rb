# frozen_string_literal: true

module SFL
  module Analysis
    # Builds aggregated profiles for speakers/sections in a conversation
    # or document. Ported faithfully from legacy's SpeakerProfiler.
    class SpeakerProfiler
      include Aggregations

      attr_reader :turns

      def initialize(turns)
        @turns = turns
      end

      # Build profile for speaker from their turns.
      # @return [Core::Types::SpeakerProfile]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one flat SpeakerProfile literal,
      # ported verbatim from legacy; each field is an independent aggregate, not extractable
      # further without just relocating this same list of assignments.
      def build_profile
        raise ArgumentError, "No turns provided" if turns.empty?

        Core::Types::SpeakerProfile.new(
          speaker_name: turns.first.speaker,
          turn_count: turns.count,
          **tenor_aggregates,
          mood_distribution: calculate_mood_distribution,
          dominant_processes: aggregate_process_types
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Build profiles for all speakers in conversation.
      # @param all_turns [Array<Core::Types::ConversationTurn>]
      # @return [Hash{String => Core::Types::SpeakerProfile}]
      def self.build_profiles(all_turns)
        all_turns.group_by(&:speaker).transform_values do |speaker_turns|
          new(speaker_turns).build_profile
        end
      end

      # Absence, not a fabricated midpoint: with no annotated turn to average
      # there is no aggregate to report, and nil is the only honest answer.
      private def tenor_aggregates
        annotated = turns.select { |turn| annotated?(turn) }
        return { avg_tenor: nil, tenor_range: nil, tenor_variance: nil, avg_modality: nil } if annotated.empty?

        tenors = annotated.map(&:avg_tenor)
        {
          avg_tenor: mean(tenors),
          tenor_range: tenors.minmax,
          tenor_variance: variance(tenors),
          avg_modality: mean(annotated.map(&:avg_modality)),
        }
      end

      # A turn whose clauses were all defaulted by Pass 2 has an avg_tenor/
      # avg_modality of 0.5 that measures nothing — averaging those in is what
      # produced two speakers both reporting tenor 0.5 with variance 0.0 off a
      # run where the provider returned nothing at all. Only turns with at
      # least one trusted (llm/human) clause contribute to the aggregates;
      # turn_count, mood_distribution and dominant_processes still cover every
      # turn, because those come from Pass 1 and are not placeholders.
      private def annotated?(turn)
        turn.clauses.any? do |clause|
          Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(clause.interpersonal.annotation_source)
        end
      end

      private def calculate_mood_distribution
        mood_counts = turns.each_with_object(Hash.new(0)) do |turn, counts|
          counts[turn.dominant_mood] += 1
        end

        total = turns.count.to_f
        mood_counts.transform_values { |count| (count / total).round(3) }
      end

      private def aggregate_process_types
        turns.each_with_object(Hash.new(0)) do |turn, totals|
          turn.process_types.each do |process_type, count|
            totals[process_type] += count
          end
        end
      end

      private def variance(values)
        return 0.0 if values.count < 2

        avg = mean(values)
        sum_squares = values.sum { |v| (v - avg) ** 2 }
        (sum_squares / values.count.to_f).round(4)
      end
    end
  end
end
