# frozen_string_literal: true

module SFL
  module Analysis
    # Compares each speaker's process-type mix against the conversation's
    # material baseline.
    #
    # Input: Array<Hash> of clauses, each with :speaker, :process_type (one of
    # Core::Types::ProcessType) and :source (the annotation source). Only
    # clauses whose :source is in Core::Types::TRUSTED_ANNOTATION_SOURCES
    # ("llm", "human") count. This is the rule CorrelationAnalyzer applies.
    #
    # Output:
    #   {baseline: {process_type => share},
    #    per_speaker: {speaker => {distribution:, deviation:, total_deviation:}}}
    #
    # - baseline: the process-type distribution of all trusted clauses. Keys are
    #   the process types that occur among them. Shares are count / total.
    # - distribution: the speaker's share per baseline type (0.0 when absent).
    # - deviation: the speaker's share minus the baseline share, per baseline type.
    # - total_deviation: half the L1 distance between the speaker's distribution
    #   and the baseline (total variation distance).
    #
    # Empty input, or input with no trusted clauses, yields empty baseline and
    # per_speaker. Nothing is read from disk.
    class ProcessMixAnalyzer
      def initialize(clauses)
        @clauses = clauses.select { |clause| trusted?(clause) }
      end

      def call
        baseline = shares(@clauses, @clauses.map { |clause| clause[:process_type] }.uniq)
        per_speaker = @clauses.group_by { |clause| clause[:speaker] }.transform_values do |speaker_clauses|
          speaker_profile(speaker_clauses, baseline)
        end

        { baseline:, per_speaker: }
      end

      private def trusted?(clause)
        Core::Types::TRUSTED_ANNOTATION_SOURCES.include?(clause[:source])
      end

      private def speaker_profile(clauses, baseline)
        distribution = shares(clauses, baseline.keys)
        deviation = baseline.to_h { |type, share| [type, distribution[type] - share] }

        { distribution:, deviation:, total_deviation: deviation.values.sum(&:abs) / 2.0 }
      end

      private def shares(clauses, types)
        counts = clauses.map { |clause| clause[:process_type] }.tally
        types.to_h { |type| [type, counts.fetch(type, 0).fdiv(clauses.size)] }
      end
    end
  end
end
