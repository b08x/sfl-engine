# frozen_string_literal: true

module SFL
  module Ingest
    # Free/instant fast-path classification: the extension- and JSON-key-
    # sniffing checks Analysis::ChatExportExpander/Analysis::KnowledgeBaseSource
    # already implement, unified into one entry point Ingest::Orchestrator
    # consults before ever calling Core::Ports::Classifier. Behavior is
    # unchanged from today for every already-supported file type — this
    # module delegates to (not reimplements) the existing dispatch logic,
    # so there is exactly one place each of those rules lives.
    module DeterministicRules
      NATIVE_CHAT_EXTENSIONS = %w[.jsonl .srt .vtt .ass].freeze

      KB_EXTENSION_FORMATS = {
        ".md" => "markdown",
        ".canvas" => "canvas",
        ".pdf" => "pdf",
      }.freeze

      KB_EXTENSION_SOURCE_TYPES = {
        ".md" => "vault_markdown",
        ".canvas" => "vault_canvas",
        ".pdf" => "vault_pdf",
      }.freeze

      # @param path [String]
      # @return [Hash{format:, mode:, source_type:}, nil] nil = no deterministic match,
      #   caller should fall through to Core::Ports::Classifier
      module_function def classify(path)
        ext = File.extname(path).downcase

        return classify_native_chat if NATIVE_CHAT_EXTENSIONS.include?(ext)
        return classify_kb_extension(ext) if Analysis::KnowledgeBaseSource::TEXT_EXTENSIONS.include?(ext)
        return classify_image(ext) if Core::Loaders::ImageSource::SUPPORTED_EXTENSIONS.include?(ext)
        return classify_json_export(path) if ext == ".json"

        nil
      end

      module_function def classify_native_chat
        { format: "chat_native", mode: "conversation", source_type: "chat_native" }
      end

      module_function def classify_kb_extension(ext)
        {
          format: KB_EXTENSION_FORMATS.fetch(ext),
          mode: "knowledge_base",
          source_type: KB_EXTENSION_SOURCE_TYPES.fetch(ext),
        }
      end

      module_function def classify_image(_ext)
        { format: "image", mode: "knowledge_base", source_type: "vault_image" }
      end

      # Delegates to Analysis::ChatExportExpander's existing JSON-key sniff
      # (lib/sfl/analysis/chat_export_expander.rb:37-47) rather than
      # re-reading/re-parsing the file a second time with different logic.
      module_function def classify_json_export(path)
        format = Analysis::ChatExportExpander.detect_format(path)
        case format
        when :chatgpt then { format: "chatgpt_export", mode: "conversation", source_type: "chat_chatgpt" }
        when :claude then { format: "claude_export", mode: "conversation", source_type: "chat_claude" }
        end
      rescue Core::Loaders::Error
        nil # malformed/unparseable JSON is not a deterministic match — fall through to the classifier
      end
    end
  end
end
