# frozen_string_literal: true

require "json"

module SFL
  module Analysis
    # Turns a JSONL conversation ({name, send_date, mes} per line) or a
    # subtitle transcript (.srt/.vtt/.ass, via Core::Loaders::SubtitleSource)
    # into the Core::Loaders::Source duck Analysis::Engine drives — the
    # same each_unit/units contract every Phase 1 loader already
    # implements (Core::Types::Unit is exactly the turn/section shape
    # legacy's ConversationAnalyzer and DocumentationAnalyzer each
    # hand-derived their own document_id/speaker/timestamp from; reusing
    # it here means Engine never needs a second "give me the raw chunks"
    # concept).
    #
    # Ported from legacy's ConversationAnalyzer.load_turns/.load_jsonl
    # dispatch, ConversationAnalyzer's document_id derivation
    # ("#{conversation_id}#turn-#{turn_id}"), and its audio-modality-gated
    # review-queue policy (#review_entry below).
    class ConversationSource
      include Core::Loaders::Source

      # @param path [String] a .jsonl conversation or .srt/.vtt/.ass transcript
      # @param source_type [String] provenance tag for review-queue entries —
      #   "chat_native" for the built-in {name, mes, send_date} JSONL format;
      #   pass e.g. "chat_claude"/"chat_chatgpt" for exports normalized by a
      #   chat-export loader upstream.
      def initialize(path, source_type: "chat_native")
        @path = path.to_s
        @source_type = source_type
        @conversation_id = File.basename(@path, ".*")
        @audio_modality = %w[.srt .vtt .ass].include?(File.extname(@path).downcase)
      end

      attr_reader :conversation_id, :audio_modality
      alias audio_modality? audio_modality

      def each_unit(&)
        return to_enum(:each_unit) unless block_given?

        if @audio_modality
          Core::Loaders::SubtitleSource.new(@path, file_id: @conversation_id).each_unit(&)
        else
          raw_turns.each_with_index { |turn_data, idx| yield build_unit(turn_data, idx) }
        end
      end

      # Engine calls this per compiled turn to decide whether (and how) to
      # enqueue a review-queue entry. nil means "don't enqueue" — mirrors
      # legacy's `enqueue_for_review(...) if store && audio_modality`: a
      # native JSONL conversation is never enqueued (its stub/fallback
      # annotations aren't a *transcription-quality* concern the way an
      # ASR-derived transcript's text is).
      # @param unit [Core::Types::Unit]
      # @param clauses [Array<Core::Types::AnnotatedClause>] unused here (see
      #   DocumentationSource for a policy that inspects clauses)
      # @return [Hash, nil]
      def review_entry(unit:, clauses:) # rubocop:disable Lint/UnusedMethodArgument -- shared Source#review_entry contract
        return nil unless @audio_modality

        { modality: "audio", reason: "audio_transcript", generated_text: unit.text, source_type: @source_type }
      end

      # Source-specific extras merged into Analysis::Engine's common
      # AnalysisResult metadata Hash. ConversationSource adds nothing
      # beyond the common fields Engine already builds.
      def extra_metadata(_turns) = {}

      private def raw_turns
        raise Core::Loaders::Error, "Unsupported conversation input format: #{File.extname(@path)}" unless
          File.extname(@path).casecmp(".jsonl").zero?

        load_jsonl
      end

      # Skips lines that parse as valid JSON but aren't turn-shaped — e.g.
      # SillyTavern group-chat exports prepend a {chat_metadata:, ...}
      # header record before the actual {name:, mes:, send_date:, ...}
      # turns, which JSON::ParserError can't catch (syntactically valid).
      private def load_jsonl
        turns = File.readlines(@path).filter_map do |line|
          turn = JSON.parse(line.strip, symbolize_names: true)
          turn if turn.is_a?(Hash) && turn[:mes]
        rescue JSON::ParserError
          nil
        end
        raise Core::Loaders::Error, "No turns found in #{@path}" if turns.empty?

        turns
      end

      private def build_unit(turn_data, idx)
        Core::Types::Unit.new(
          document_id: "#{@conversation_id}#turn-#{idx + 1}",
          text: turn_data[:mes],
          speaker: turn_data[:name],
          is_user: turn_data[:is_user],
          sent_at: parse_timestamp(turn_data[:send_date]),
          metadata: { "conversation_id" => @conversation_id }
        )
      end

      private def parse_timestamp(value)
        Time.parse(value.to_s)
      rescue ArgumentError, TypeError
        Time.now
      end
    end
  end
end
