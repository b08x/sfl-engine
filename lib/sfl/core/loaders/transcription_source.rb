# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Normalizes a plain-line transcription file (transcription_*.txt in
      # ~/Notebook/Daily — one spoken line per physical line, no speaker
      # labels, no timestamp markers) into Types::Unit turns. One file is
      # one document in the glossary sense; each non-blank physical line is
      # one section — a turn spoken by the user who dictated it.
      #
      # Consolidates and replaces the three candidate drafts from 4a53727
      # (TranscriptionChatSource, TranscriptionLoader and
      # TranscriptionTextLoader), resolving their speaker conflict ("User"
      # vs "Unknown") and their timestamp conflict (Time.now per line vs
      # none) as user-approved: every turn carries the SPEAKER constant
      # ("User") with is_user true, and sent_at is the ref's mtime — or the
      # load time when the ref has none (a git-tree ref), the same
      # base-time fallback SubtitleSource#merge_into_turns applies.
      #
      # Content is data, never interpreted (STRIDE tampering): a line that
      # looks like a code fence, a heading, a "[Speaker 1]" label or a URL
      # is emitted verbatim as its own turn's text. Blank and
      # whitespace-only lines are skipped silently — no turn, no warning;
      # turn ids count emitted turns only. Fatal cases (a non-.txt ref, a
      # zero-byte or blank-only file) raise Loaders::Error for the ingest
      # boundary to rescue.
      class TranscriptionSource
        include Source

        # Every line was dictated by the user who owns the vault — defined
        # once here, not per line or per file.
        SPEAKER = "User"

        # @param ref [SFL::Core::Refs::FileRef] a .txt ref whose lines are spoken text
        # @param file_id [String, nil] section id prefix; defaults to FileId.call(ref)
        def initialize(ref, file_id: nil)
          @ref = ref
          @file_id = file_id || FileId.call(ref)
        end

        # @yield [Types::Unit] one turn per non-blank line, in file order
        # @return [Enumerator] when no block is given
        def each_unit
          return to_enum(:each_unit) unless block_given?

          lines = spoken_lines
          raise Loaders::Error, "No spoken lines in #{file_name}" if lines.empty?

          base_time = @ref.mtime || Time.now
          lines.each_with_index { |line, index| yield build_unit(line, index, base_time) }
        end

        # Analysis::Engine's optional review hook (see
        # Analysis::ConversationSource for the pattern): a transcription is
        # enqueued for review through the ingest-review queue when its
        # dispatch fails, never through the audio-modality review queue, so
        # there is no entry to contribute here.
        def review_entry(unit:, clauses:) # rubocop:disable Lint/UnusedMethodArgument -- shared Source duck contract
          nil
        end

        # Analysis::Engine's optional metadata hook: a transcription adds
        # nothing beyond the common fields Engine already builds.
        def extra_metadata(_turns) = {}

        private def build_unit(line, index, base_time)
          Types::Unit.new(
            section_id: "#{@file_id}#turn-#{index}",
            text: line,
            speaker: SPEAKER,
            is_user: true,
            document_key: @ref.path_hint,
            source_path: @ref.path_hint,
            sent_at: base_time,
            metadata: { "file_id" => @file_id }
          )
        end

        private def spoken_lines
          raise Loaders::Error, unsupported_extension_message unless txt?

          @ref.read.lines.map(&:strip).reject(&:empty?)
        end

        private def unsupported_extension_message
          "Unsupported transcription format #{file_name}: expected a .txt ref"
        end

        private def txt? = @ref.extension.casecmp(".txt").zero?

        private def file_name = "#{@ref.name}#{@ref.extension}"
      end
    end
  end
end
