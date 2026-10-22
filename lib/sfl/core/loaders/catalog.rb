# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Registers every leaf loader into a Core::Registry so loaders can
      # be resolved by name at boot (SFL-ING-02). Composite loaders
      # (ConversationSource, DocumentationSource, KnowledgeBaseSource)
      # are deliberately excluded — they orchestrate leaf loaders, they
      # are not leaf strategies themselves.
      module Catalog
        # @param registry [SFL::Core::Registry]
        # @return [void]
        def self.register_into(registry)
          register_simple(registry)
          register_with_required_kwargs(registry)
        end

        # Loaders whose factories only need ref + optional kwargs.
        def self.register_simple(registry)
          registry.register(:markdown) { |ref:, **o| MarkdownSource.new(ref, **o) }
          registry.register(:pdf) { |ref:, **o| PdfSource.new(ref, **o) }
          registry.register(:canvas) { |ref:, **o| CanvasSource.new(ref, **o) }
          registry.register(:subtitle) { |ref:, **o| SubtitleSource.new(ref, **o) }
          registry.register(:transcription) { |ref:, **o| TranscriptionSource.new(ref, **o) }
          registry.register(:image_meta) { |ref:, **o| ImageMetaSource.new(ref, **o) }
          registry.register(:chatgpt_export) { |ref:, **o| ChatgptExportSource.new(ref, **o) }
          registry.register(:claude_export) { |ref:, **o| ClaudeExportSource.new(ref, **o) }
          registry.register(:mistral_export) { |ref:, **o| MistralExportSource.new(ref, **o) }
        end

        # Loaders whose factories require additional mandatory kwargs.
        def self.register_with_required_kwargs(registry)
          registry.register(:image) { |ref:, chat:, **o| ImageSource.new(ref, chat:, **o) }
          registry.register(:json) { |ref:, text_key:, **o| JsonSource.new(ref, text_key:, **o) }
          registry.register(:csv) { |ref:, text_column:, **o| CsvSource.new(ref, text_column:, **o) }
        end

        private_class_method :register_simple, :register_with_required_kwargs
      end
    end
  end
end
