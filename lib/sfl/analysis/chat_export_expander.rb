# frozen_string_literal: true

require "json"
require "fileutils"

module SFL
  module Analysis
    # Expands a raw multi-conversation chat export (ChatGPT or Claude.ai
    # conversations.json) into one native {name:, mes:, send_date:} JSONL
    # file per conversation, materialized under `dest_dir` — the format
    # Analysis::ConversationSource already knows how to drive.
    #
    # Closes a gap ConversationSource's own doc comment anticipated but
    # nothing ever actually wired: "pass e.g. chat_claude/chat_chatgpt
    # source_type for exports normalized by a chat-export loader
    # upstream." Core::Loaders::ChatgptExportSource/ClaudeExportSource
    # existed and worked; CLI.run_conversation never called either.
    # Live-verified gap (2026-08-02): pointing `sfl-analyze conversation`
    # directly at a raw conversations.json raised deep inside
    # ConversationSource#raw_turns ("Unsupported conversation input
    # format: .json") instead of being accepted, because a *single* file
    # argument skips run_conversation's own .{jsonl,srt,vtt,ass} glob
    # filter entirely (that filter only applies in directory mode).
    #
    # One JSONL file per conversation, not one Engine#analyze call across
    # the whole export, because conversation-level aggregation
    # (SpeakerProfile, KeyMoment tenor/modality shifts) is only meaningful
    # within a single conversation — mashing hundreds of unrelated
    # conversations into one AnalysisResult would produce nonsense "key
    # moments" at conversation boundaries.
    module ChatExportExpander
      # @param path [String] raw export .json path
      # @return [Symbol, nil] :chatgpt, :claude, or nil if neither shape matches
      # @raise [Core::Loaders::Error] the file is not valid JSON — with path context, since a
      #   bare JSON::ParserError gives no indication which file in a batch failed (live-verified
      #   gap, 2026-08-02: this used to propagate unwrapped past every rescue clause in the CLI).
      module_function def detect_format(path)
        parsed = parse_json_with_context(path)
        parsed = parsed["conversations"] if parsed.is_a?(Hash) && parsed["conversations"].is_a?(Array)
        first = parsed.first if parsed.respond_to?(:first)
        return nil unless first.is_a?(Hash)

        return :chatgpt if first.key?("mapping")
        return :claude if first.key?("chat_messages")

        nil
      end

      module_function def parse_json_with_context(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Core::Loaders::Error, "#{path}: invalid JSON (#{e.message})"
      end

      # @param path [String] raw export .json path
      # @param dest_dir [String] directory to write one .jsonl file per conversation into
      # @param format [Symbol, nil] :chatgpt/:claude, or nil to auto-detect
      # @return [Array<Hash>] {path:, source_type:, label:} per conversation, export order
      # @raise [Core::Loaders::Error] neither format's shape matches
      module_function def expand(path, dest_dir:, format: nil)
        format ||= detect_format(path)
        unless format
          raise Core::Loaders::Error, "#{path}: not a recognized ChatGPT/Claude export (no top-level " \
            "\"mapping\" or \"chat_messages\" key found)"
        end

        loader, source_type = loader_for(format, path)
        FileUtils.mkdir_p(dest_dir)
        write_per_conversation_jsonl(loader, dest_dir, source_type)
      end

      module_function def loader_for(format, path)
        case format
        when :chatgpt then [Core::Loaders::ChatgptExportSource.new(path), "chat_chatgpt"]
        when :claude then [Core::Loaders::ClaudeExportSource.new(path), "chat_claude"]
        else raise ArgumentError, "unknown format #{format.inspect}"
        end
      end

      # collect sequence; splitting further would only relocate, not reduce, this.
      module_function def write_per_conversation_jsonl(loader, dest_dir, source_type)
        entries = {}
        loader.each_unit do |unit|
          conversation_id = unit.metadata.fetch("conversation_id")
          entry = entries[conversation_id] ||= build_entry(unit, dest_dir, source_type)
          entry[:io].puts(JSON.dump(
            name: unit.speaker, mes: unit.text, send_date: unit.sent_at&.iso8601, is_user: unit.is_user
          ))
        end

        entries.each_value { |entry| entry[:io].close }
        entries.each_value.map { |entry| entry.slice(:path, :source_type, :label) }
      end
      # The id-fragment suffix is load-bearing, not cosmetic: two
      # conversations can share a title (a common real-export shape —
      # "Untitled", duplicated names), and slug-only filenames would
      # silently collide — the second File.open(path, "w") truncating
      # the first conversation's already-written data rather than erroring.
      module_function def build_entry(unit, dest_dir, source_type)
        conversation_id = unit.metadata.fetch("conversation_id")
        title_slug = slugify(unit.metadata["conversation_title"] || conversation_id)
        path = File.join(dest_dir, "#{title_slug}-#{conversation_id[0, 8]}.jsonl")
        { path:, io: File.open(path, "w"), source_type:, label: title_slug }
      end

      module_function def slugify(text)
        slug = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
        slug.empty? ? "conversation" : slug
      end
    end
  end
end
