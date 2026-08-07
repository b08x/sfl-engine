# frozen_string_literal: true

require "fileutils"

module SFL
  module Ingest
    # Drafts a candidate SFL::Core::Loaders::Source subclass for a file
    # shape Ingest::DeterministicRules/Core::Ports::Classifier couldn't
    # recognize at all (tier: loader_drafting — see SFL::Boot).
    #
    # Safety boundary: never requires, registers, or executes the drafted
    # file. It is written to `loaders_dir` inert — a human must review it,
    # then manually add the `require` and a DeterministicRules table
    # entry before it runs against real data. No code path in this class
    # or Ingest::Orchestrator loads it automatically.
    class LoaderDrafter
      class Error < SFL::Error; end

      # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
      # @param loaders_dir [String] where candidate loader .rb files are written
      # @param docs_dir [String] where candidate review .md docs are written
      def initialize(chat:, loaders_dir: "lib/sfl/core/loaders", docs_dir: "docs/ingest-review")
        @chat = chat
        @loaders_dir = loaders_dir
        @docs_dir = docs_dir
      end

      # @param sample [String]
      # @param path [String] the original file's path, for the doc's context
      # @return [Hash{loader_path:, doc_path:}]
      # @raise [Error] the LLM call or schema validation failed
      def draft(sample, path)
        raw = fetch(sample, path)
        write_files(raw, path)
      rescue Error
        raise
      rescue => e
        raise Error, "loader draft failed for #{path}: #{e.message}"
      end

      attr_reader :chat, :loaders_dir, :docs_dir
      private :chat, :loaders_dir, :docs_dir

      private def fetch(sample, path)
        prompt = Prompts.render(:loader_drafting, path:, sample:)
        response = chat.with_schema(LLM::Schemas::LoaderDraftSchema).ask(prompt)
        LLM::ResponseSymbolizer.call(response.content)
      end

      # Untrusted LLM output: class_name feeds directly into a filesystem path below
      # (loaders_dir/docs_dir join), so it's constrained to a bare PascalCase identifier
      # before use — rejects path-traversal segments ("..", "/") and any other shape the
      # schema's prompt description didn't actually enforce on its own.
      CLASS_NAME_PATTERN = /\A[A-Z][A-Za-z0-9]*\z/

      private def write_files(raw, source_path)
        class_name = validated_class_name(raw.fetch(:class_name), source_path)
        file_stem = underscore(class_name)
        FileUtils.mkdir_p(loaders_dir)
        FileUtils.mkdir_p(docs_dir)

        loader_path = File.join(loaders_dir, "#{file_stem}.rb")
        doc_path = File.join(docs_dir, "#{file_stem}.md")

        File.write(loader_path, raw.fetch(:ruby_source))
        File.write(doc_path, review_doc(raw, source_path))

        { loader_path:, doc_path: }
      end

      private def validated_class_name(class_name, source_path)
        return class_name if CLASS_NAME_PATTERN.match?(class_name)

        raise Error, "loader draft for #{source_path} returned an invalid class_name: #{class_name.inspect}"
      end

      private def review_doc(raw, source_path)
        <<~MARKDOWN
          # Candidate loader: #{raw.fetch(:class_name)}

          Drafted for: `#{source_path}`
          Confidence: #{raw.fetch(:confidence)}

          ## Field mapping

          #{raw.fetch(:field_mapping_explanation)}

          ## Status

          **Not registered.** Review `#{underscore(raw.fetch(:class_name))}.rb`, then wire it in:
          add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
          loader runs against real data.
        MARKDOWN
      end

      # PascalCase -> snake_case, no external inflector dependency needed for this one shape.
      # Known limitation: doesn't split consecutive-capital acronym runs (e.g. "JSONLChatSource"
      # -> "jsonlchat_source", not "jsonl_chat_source") — acceptable because a human reviews and,
      # if registering the draft, renames the class/file together; CLASS_NAME_PATTERN above only
      # guards the security boundary (no path-traversal/separator characters), not naming taste.
      private def underscore(class_name)
        class_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
