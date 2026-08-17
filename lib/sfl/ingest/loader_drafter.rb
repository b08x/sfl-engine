# frozen_string_literal: true

require "fileutils"
require "dspy"

module SFL
  module Ingest
    # Drafts a candidate SFL::Core::Loaders::Source subclass for a file
    # shape Ingest::DeterministicRules/Core::Ports::Classifier couldn't
    # recognize at all (tier: loader_drafting — see SFL::Boot).
    class LoaderDrafter
      class Error < SFL::Error; end

      # @param lm [DSPy::LM] The language model configuration for this task
      # @param loaders_dir [String] where candidate loader .rb files are written
      # @param docs_dir [String] where candidate review .md docs are written
      def initialize(lm:, loaders_dir: "lib/sfl/core/loaders", docs_dir: "docs/ingest-review")
        @lm = lm
        @predictor = DSPy::Predict.new(LLM::Signatures::LoaderDraftSignature).tap do |p|
          p.configure { |c| c.lm = lm }
        end
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

      attr_reader :lm, :loaders_dir, :docs_dir
      private :lm, :loaders_dir, :docs_dir

      private def fetch(sample, path)
        # We can still render the prompt, or just pass them as inputs. Let's just pass them as inputs.
        # But wait, did LoaderDraftSignature expect "prompt" or "file_sample" and "filename"?
        # It expects `file_sample` and `filename`.
        result = @predictor.call(file_sample: sample, filename: path)
        LLM::ResponseSymbolizer.call(result.to_h)
      end

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

      private def underscore(class_name)
        class_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
