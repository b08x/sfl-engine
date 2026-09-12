# frozen_string_literal: true

require "time"

module SFL
  module Core
    module Loaders
      # Normalizes SRT/VTT/ASS subtitle files into Types::Unit turns.
      # Ported from legacy SubtitleLoader (logic unchanged) — see
      # ChatgptExportSource/ClaudeExportSource for the sibling convention
      # this follows for turn-shaped sources. Unlike those, a subtitle
      # file is inherently one conversation (no multi-conversation
      # bundling), so #each_unit yields turns directly.
      #
      # Cue merging: consecutive cues from the same speaker are merged
      # into one turn — a turn boundary is a speaker change, nothing else
      # — because karaoke-style captions split one spoken sentence across
      # many cue lines, and per-cue turns would shred it into fragments.
      # Formats or files with no speaker information (plain SRT, or an
      # ASS file where every Dialogue uses the same Name) fall back to
      # one synthetic speaker for the whole file, which means — as a
      # direct consequence of the same rule — every cue merges into a
      # single turn: there is no dialogue structure to recover, so the
      # transcript is treated as one continuous monologue/narration.
      # rubocop:disable Metrics/ClassLength -- three independent subtitle-format grammars
      # (SRT/VTT/ASS), each already its own private parse method; this is the sum of three
      # small parsers plus the shared cue-merge step, not one long method.
      class SubtitleSource
        include Source

        Cue = Struct.new(:speaker, :start_offset, :text, keyword_init: true)

        SYNTHETIC_SPEAKER = "Speaker"

        # @param path [String, Pathname]
        # @param file_id [String, nil]
        def initialize(path, file_id: nil)
          @path = path.to_s
          @file_id = file_id || File.basename(@path, ".*")
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          cues = parse
          raise Loaders::Error, "No cues found in #{@path}" if cues.empty?

          merge_into_turns(cues).each_with_index { |turn, index| yield build_unit(turn, index) }
        end

        private def build_unit(turn, index)
          Types::Unit.new(
            document_id: "#{@file_id}#turn-#{index}",
            text: turn[:mes],
            speaker: turn[:name],
            is_user: turn[:is_user],
            sent_at: turn[:send_date] ? Time.parse(turn[:send_date]) : nil,
            metadata: { "file_id" => @file_id }
          )
        end

        private def parse
          case File.extname(@path).downcase
          when ".srt" then parse_srt
          when ".vtt" then parse_vtt
          when ".ass" then parse_ass
          else raise Loaders::Error, "Unsupported subtitle format: #{File.extname(@path)}"
          end
        end

        SRT_TIMECODE = /^(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->/

        # for one subtitle grammar; splitting the timecode-match/text-join/Cue-build steps into
        # separate methods would scatter one format's parsing across the file for no reader benefit.
        private def parse_srt
          blocks = File.read(@path).split(/\r?\n\r?\n+/).map(&:strip).reject(&:empty?)

          blocks.filter_map do |block|
            lines = block.lines.map(&:chomp)
            timecode_index = lines.index { |line| line.match?(SRT_TIMECODE) }
            if timecode_index.nil?
              warn "[WARN] malformed SRT cue skipped (no timecode line): #{lines.first.inspect}"
              next nil
            end

            match = lines[timecode_index].match(SRT_TIMECODE)
            start_offset = hms_to_seconds(match[1], match[2], match[3], match[4], 1000.0)
            text = lines[(timecode_index + 1)..].join(" ").strip
            next nil if text.empty?

            Cue.new(speaker: nil, start_offset:, text:)
          end
        end
        # rubocop:disable Naming/MethodParameterName -- h/m/s/frac name exactly what they are
        # (hours/minutes/seconds/fractional-seconds) at the one regex-match call site; longer
        # names would just repeat "timecode_" four times for no added clarity.
        private def hms_to_seconds(h, m, s, frac, frac_scale)
          (h.to_i * 3600) + (m.to_i * 60) + s.to_i + (frac.to_i / frac_scale)
        end
        # rubocop:enable Naming/MethodParameterName

        VTT_TIMECODE = /^(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})\s*-->/
        VTT_VOICE_TAG = /^<v\s+([^>]+)>\s*/

        # one cohesive parse routine for one subtitle grammar, including VTT's optional <v>
        # voice-tag extraction; same rationale as #parse_srt.
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        private def parse_vtt
          blocks = File.read(@path).split(/\r?\n\r?\n+/).map(&:strip).reject(&:empty?)

          blocks.filter_map do |block|
            lines = block.lines.map(&:chomp)
            next nil if lines.first&.start_with?("WEBVTT")
            next nil if lines.first&.start_with?("NOTE")
            next nil if %w[STYLE REGION].include?(lines.first)

            timecode_index = lines.index { |line| line.match?(VTT_TIMECODE) }
            if timecode_index.nil?
              warn "[WARN] malformed VTT cue skipped (no timecode line): #{lines.first.inspect}"
              next nil
            end

            match = lines[timecode_index].match(VTT_TIMECODE)
            start_offset = hms_to_seconds(match[1], match[2], match[3], match[4], 1000.0)
            text = lines[(timecode_index + 1)..].join(" ").strip
            next nil if text.empty?

            speaker = nil
            if (voice_match = text.match(VTT_VOICE_TAG))
              speaker = voice_match[1].strip
              text = text.sub(VTT_VOICE_TAG, "").sub("</v>", "").strip
            end

            Cue.new(speaker:, start_offset:, text:)
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        ASS_TIMECODE = /^(\d+):(\d{2}):(\d{2})\.(\d{2})$/
        ASS_OVERRIDE_TAG = /\{[^}]*\}/

        # one cohesive parse routine for ASS's own grammar (header-column lookup by name, then
        # per-Dialogue-line field extraction); same rationale as #parse_srt/#parse_vtt.
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        private def parse_ass
          lines = File.read(@path).lines.map(&:chomp)
          events_index = lines.index { |l| l.strip == "[Events]" }
          return [] if events_index.nil?

          section = lines[(events_index + 1)..].take_while { |l| !l.start_with?("[") }
          format_line = section.find { |l| l.start_with?("Format:") }
          return [] if format_line.nil?

          columns = format_line.sub("Format:", "").split(",").map(&:strip)
          text_index = columns.index("Text")
          start_index = columns.index("Start")
          name_index = columns.index("Name")

          section.select { |l| l.start_with?("Dialogue:") }.filter_map do |line|
            fields = line.sub("Dialogue:", "").strip.split(",", columns.size)
            if fields.size != columns.size
              warn "[WARN] malformed ASS Dialogue line skipped (field count mismatch): #{line.inspect}"
              next nil
            end

            start_match = fields[start_index].strip.match(ASS_TIMECODE)
            if start_match.nil?
              warn "[WARN] malformed ASS Dialogue line skipped (bad Start timecode): #{line.inspect}"
              next nil
            end

            start_offset = hms_to_seconds(start_match[1], start_match[2], start_match[3], start_match[4], 100.0)
            text = fields[text_index].gsub(ASS_OVERRIDE_TAG, "").gsub(/\\N|\\n/, " ").strip
            next nil if text.empty?

            speaker = fields[name_index]&.strip
            speaker = nil if speaker && speaker.empty?

            Cue.new(speaker:, start_offset:, text:)
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        # new-turn-Hash branch are two halves of one rule (see the class doc comment on cue
        # merging), not independently extractable steps.
        private def merge_into_turns(cues)
          base_time = File.mtime(@path)
          turns = []

          cues.each do |cue|
            speaker = cue.speaker || SYNTHETIC_SPEAKER
            current = turns.last

            if current && current[:name] == speaker
              current[:mes] = "#{current[:mes]} #{cue.text}"
            else
              turns << {
                name: speaker,
                is_user: false,
                send_date: (base_time + cue.start_offset).iso8601,
                mes: cue.text,
              }
            end
          end

          turns
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
