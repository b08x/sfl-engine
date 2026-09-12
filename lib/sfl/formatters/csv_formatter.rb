# frozen_string_literal: true

require "csv"

module SFL
  module Formatters
    # Exports conversation analysis to CSV format.
    class CSVFormatter < BaseFormatter
      def render
        CSV.generate do |csv|
          csv << headers
          result.turns.each do |turn|
            csv << turn_to_row(turn)
          end
        end
      end

      private def headers
        %w[
          turn_id
          speaker
          timestamp
          message_preview
          avg_tenor
          avg_modality
          dominant_mood
          process_counts
          participants
          tenor_shift
          semantic_coherence_score
        ]
      end
      # ported verbatim from legacy.
      private def turn_to_row(turn)
        [
          turn.turn_id,
          turn.speaker,
          turn.timestamp.strftime("%Y-%m-%d %H:%M"),
          truncate_message(turn.message_text),
          turn.avg_tenor.round(2),
          turn.avg_modality.round(2),
          turn.dominant_mood,
          format_process_counts(turn.process_types),
          turn.participants.join(" "),
          turn.tenor_shift ? format("%.2f", turn.tenor_shift) : "",
          turn.semantic_coherence_score ? format("%.2f", turn.semantic_coherence_score) : "",
        ]
      end
      private def truncate_message(text, max_length: 50)
        (text.length > max_length) ? "#{text[0...max_length]}..." : text
      end

      private def format_process_counts(process_types)
        process_types.map { |type, count| "#{type}:#{count}" }.join(" ")
      end
    end
  end
end
