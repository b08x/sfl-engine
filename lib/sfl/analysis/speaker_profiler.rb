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

        speaker_name = turns.first.speaker
        tenors = turns.map(&:avg_tenor)
        modalities = turns.map(&:avg_modality)

        Core::Types::SpeakerProfile.new(
          speaker_name:,
          turn_count: turns.count,
          avg_tenor: mean(tenors),
          tenor_range: tenors.minmax,
          tenor_variance: variance(tenors),
          avg_modality: mean(modalities),
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
