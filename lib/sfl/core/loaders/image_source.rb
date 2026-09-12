# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Pre-processor for image files (.png, .jpg, .jpeg, .webp): uses a
      # vision-capable chat (injected, per this codebase's DI convention —
      # legacy ImageLoader called the RubyLLM.chat global directly and did
      # its own model-id/provider resolution; that resolution job now
      # belongs to per-task Config/ChatFactory, decision 8, not this
      # class) to extract a text description, fed into the pipeline as
      # prose. Falls back to a minimal stub (filename + format) if the
      # call fails — the unit is still emitted with a truthful
      # "vision_failed" metadata flag rather than silently dropped.
      class ImageSource
        include Source

        SUPPORTED_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze

        VISION_PROMPT = <<~PROMPT
          Describe the content of this image in plain prose, focusing on:
          - Any visible text, labels, or captions
          - The type of image (diagram, screenshot, photo, chart, etc.)
          - Key concepts or subjects depicted
          - Technical details if this is a diagram or code screenshot
          Write 2-5 sentences. Do not use bullet points.
        PROMPT

        # @param path [String, Pathname]
        # @param chat [#ask] a vision-capable RubyLLM::Chat (or compatible double)
        # @param file_id [String, nil]
        def initialize(path, chat:, file_id: nil)
          @path = path.to_s
          @chat = chat
          @file_id = file_id || File.basename(@path, ".*")
        end

        def each_unit
          return to_enum(:each_unit) unless block_given?

          text, failed = describe_image
          return if text.nil? || text.strip.empty?

          yield build_unit(text, failed)
        end

        attr_reader :chat
        private :chat

        # @return [Array(String, Boolean)] description text, and whether vision failed
        private def describe_image
          response = chat.ask(VISION_PROMPT, with: { image: @path })
          [response.content&.strip, false]
        rescue => e
          warn "[WARN] ImageSource: vision call failed for #{File.basename(@path)}: #{e.message}"
          [fallback_description, true]
        end

        private def fallback_description
          ext = File.extname(@path).delete(".").upcase
          size_kb = (File.size(@path) / 1024.0).round(1)
          "#{ext} image file: #{File.basename(@path)} (#{size_kb} KB). Visual content could not be extracted."
        end

        # is a distinct fact about the source image, not padding.
        private def build_unit(text, vision_failed)
          Types::Unit.new(
            document_id: "#{@file_id}#image",
            text:,
            heading: "Image: #{File.basename(@path)}",
            metadata: {
              "file_id" => @file_id,
              "content_type" => "image",
              "source_path" => @path,
              "format" => File.extname(@path).downcase.delete("."),
              "vision_failed" => vision_failed,
            }
          )
        end
      end
    end
  end
end
