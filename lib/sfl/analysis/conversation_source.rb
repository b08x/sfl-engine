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
    # hand-derived their own section_id/speaker/timestamp from; reusing
    # it here means Engine never needs a second "give me the raw chunks"
    # concept).
    #
    # Ported from legacy's ConversationAnalyzer.load_turns/.load_jsonl
    # dispatch, ConversationAnalyzer's section_id derivation
    # ("#{conversation_id}#turn-#{turn_id}"), and its audio-modality-gated
    # review-queue policy (#review_entry below).
    class ConversationSource
      include Core::Loaders::Source

      # @param ref [SFL::Core::Refs::FileRef] a .jsonl conversation or .srt/.vtt/.ass transcript
      # @param source_type [String] provenance tag for review-queue entries —
      #   "chat_native" for the built-in {name, mes, send_date} JSONL format;
      #   pass e.g. "chat_claude"/"chat_chatgpt" for exports normalized by a
      #   chat-export loader upstream.
      def initialize(ref, source_type: "chat_native")
        @ref = ref
        @source_type = source_type
        @conversation_id = ref.name
        @file_id = Core::Loaders::FileId.call(ref)
      end

      attr_reader :conversation_id

      # True for .srt/.vtt/.ass files and for cue-shaped JSONL (detected from
      # file content, memoized on first use).
      def audio_modality
        return @audio_modality if defined?(@audio_modality)

        @audio_modality = subtitle_extension? || cue_records?
      end
      alias audio_modality? audio_modality

      def each_unit(&)
        return to_enum(:each_unit) unless block_given?

        if subtitle_extension?
          Core::Loaders::SubtitleSource.new(@ref, file_id: @file_id).each_unit(&)
        elsif cue_records?
          cue_units.each(&)
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
        return nil unless audio_modality

        { modality: "audio", reason: "audio_transcript", generated_text: unit.text, source_type: @source_type }
      end

      # Source-specific extras merged into Analysis::Engine's common
      # AnalysisResult metadata Hash. ConversationSource adds nothing
      # beyond the common fields Engine already builds.
      def extra_metadata(_turns) = {}

      private def raw_turns
        raise Core::Loaders::Error, "Unsupported conversation input format: #{@ref.extension}" unless jsonl?

        turns = records.select { |record| record.is_a?(Hash) && record[:mes] }
        raise Core::Loaders::Error, no_turns_message if turns.empty?

        turns
      end

      private def subtitle_extension? = %w[.srt .vtt .ass].include?(@ref.extension.downcase)

      private def jsonl? = @ref.extension.casecmp(".jsonl").zero?

      # Parsed JSONL records (nil-free), memoized with the line counts used by the error message.
      # Skips lines that parse as valid JSON but aren't turn-shaped — e.g.
      # SillyTavern group-chat exports prepend a {chat_metadata:, ...}
      # header record before the actual {name:, mes:, send_date:, ...}
      # turns, which JSON::ParserError can't catch (syntactically valid).
      private def records
        @records ||= begin
          @line_count = 0
          @unparseable = 0
          @ref.read.lines.map(&:strip).reject(&:empty?).filter_map do |line|
            @line_count += 1
            JSON.parse(line, symbolize_names: true)
          rescue JSON::ParserError
            @unparseable += 1
            nil
          end
        end
      end

      # Cue-shaped: some record has String text and speaker, and no record is native (:mes).
      private def cue_records?
        return false unless jsonl?

        @cue_records = compute_cue_records? unless defined?(@cue_records)
        @cue_records
      end

      private def compute_cue_records?
        hashes = records.grep(Hash)
        return false if hashes.any? { |record| record[:mes] }

        hashes.any? { |record| cue_record?(record) }
      end

      private def cue_record?(record) = record[:text].is_a?(String) && record[:speaker].is_a?(String)

      private def cue_units
        cues = records.grep(Hash).select { |record| cue_record?(record) }.filter_map do |record|
          text = record[:text].strip
          next if text.empty?

          Core::Loaders::SubtitleSource::Cue.new(
            speaker: record[:speaker], start_offset: start_offset_seconds(record[:start_ms]), text:
          )
        end
        raise Core::Loaders::Error, no_turns_message if cues.empty?

        Core::Loaders::SubtitleSource.units_from_cues(cues, ref: @ref, file_id: @file_id)
      end

      # Integer, Float or a fully numeric String of milliseconds; anything else is 0.0.
      private def start_offset_seconds(start_ms)
        number = start_ms.is_a?(String) ? Float(start_ms.strip, exception: false) : start_ms
        (number.is_a?(Numeric) && number.to_f.finite?) ? number / 1000.0 : 0.0
      end

      private def no_turns_message
        first = records.find { |record| record.is_a?(Hash) } || {}
        keys = first.keys.map(&:to_s).sort
        shown = keys.first(12)
        shown_text = (keys.size > 12) ? "#{shown.inspect[0..-2]}, ...]" : shown.inspect
        "No turns found in #{@ref.name}: read #{@line_count} line(s), #{@unparseable} unparseable; " \
          "first record keys: #{shown_text}; expected {name, mes, send_date} chat turns " \
          "or {speaker, text, start_ms} subtitle cues"
      end

      private def build_unit(turn_data, idx)
        Core::Types::Unit.new(
          section_id: "#{@file_id}#turn-#{idx + 1}",
          text: turn_data[:mes],
          speaker: turn_data[:name],
          document_key: @ref.path_hint || @conversation_id,
          source_path: @ref.path_hint,
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
