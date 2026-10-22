# frozen_string_literal: true

require "fileutils"
require "dspy"

module SFL
  module Ingest
    # Drafts a candidate SFL::Core::Loaders::Source subclass for a file
    # shape Ingest::DeterministicRules/Core::Ports::Classifier couldn't
    # recognize at all (tier: loader_drafting — see SFL::Boot).
    #
    # LLM output is untrusted DATA end to end. A draft is validated by
    # parsing it (never eval/require/load), then written into a quarantine
    # directory the Zeitwerk loader never sees. Promotion into lib/ is a
    # human copy, never a code path (incident 4a53727).
    class LoaderDrafter
      class Error < SFL::Error; end

      # A differing draft for a class name already in the quarantine;
      # existing drafts are never overwritten.
      class DuplicateDraftError < Error; end

      CLASS_NAME_PATTERN = /\A[A-Z][A-Za-z0-9]*\z/
      NAMESPACE = "SFL::Core::Loaders"

      # The promotion target is named in the review doc for the human
      # reviewer only — this class never writes, requires or loads it. It
      # is built with File.join so this source file carries no literal
      # reference to the Zeitwerk-eager-loaded tree (QA step 16).
      PROMOTION_DIR = File.join("lib", "sfl", "core", "loaders").freeze

      # @param lm [DSPy::LM] The language model configuration for this task
      # @param drafts_dir [String] quarantine for candidate loader .rb
      #   files; never inside lib/, which the Zeitwerk loader eager-loads
      # @param docs_dir [String] where candidate review .md docs are written
      # @param predictor [Object, nil] injectable predictor seam so specs
      #   can double DSPy::Predict without a network; defaults to a real one
      def initialize(lm:, drafts_dir: "docs/ingest-review/candidates",
        docs_dir: "docs/ingest-review", predictor: nil
      )
        @lm = lm
        @predictor = predictor || DSPy::Predict.new(LLM::Signatures::LoaderDraftSignature).tap do |p|
          p.configure { |c| c.lm = lm }
        end
        @drafts_dir = drafts_dir
        @docs_dir = docs_dir
      end

      # @param sample [String]
      # @param path [String] the original file's path, for the doc's context
      # @return [Hash{loader_path:, doc_path:}]
      # @raise [Error] a validation gate rejected the draft, or the
      #   predictor call itself failed
      # @raise [DuplicateDraftError] a different draft for the class name
      #   already sits in the quarantine
      def draft(sample, path)
        response = @predictor.call(file_sample: sample, filename: path)
        write_draft(LLM::ResponseSymbolizer.call(response.to_h), path)
      rescue Error
        raise
      rescue => e
        raise Error, "loader draft failed for #{path}: #{e.message}"
      end

      attr_reader :lm, :drafts_dir, :docs_dir, :predictor
      private :lm, :drafts_dir, :docs_dir, :predictor

      private def write_draft(raw, source_path)
        class_name = raw.fetch(:class_name)
        raise Error, "loader draft for #{source_path} returned an invalid class_name: #{class_name.inspect}" unless CLASS_NAME_PATTERN.match?(class_name)

        stem = underscore(class_name)
        source = raw.fetch(:ruby_source)
        begin
          ast = RubyVM::AbstractSyntaxTree.parse(source)
        rescue SyntaxError => e
          record_invalid(stem:, class_name:, source_path:, gate: "G2 (syntax parse)", reason: e.message, source:)
        end
        declared = DeclaredClasses.of(ast)
        unless declared.include?("#{NAMESPACE}::#{class_name}")
          record_invalid(stem:, class_name:, source_path:, gate: "G3 (declared class name)", source:,
            reason: "it declares #{declared.inspect}, not #{NAMESPACE}::#{class_name}")
        end
        paths = { loader_path: File.join(drafts_dir, "#{stem}.rb"), doc_path: File.join(docs_dir, "#{stem}.md") }
        if File.exist?(paths[:loader_path])
          return paths if File.read(paths[:loader_path]) == source

          raise DuplicateDraftError, "loader draft for #{source_path} would overwrite an existing draft for " \
            "#{NAMESPACE}::#{class_name} at #{paths[:loader_path]}; nothing was written"
        end
        FileUtils.mkdir_p([drafts_dir, docs_dir])
        File.write(paths[:loader_path], source)
        File.write(paths[:doc_path], review_doc(raw, source_path, paths[:loader_path]))
        paths
      end

      private def record_invalid(stem:, class_name:, source_path:, gate:, reason:, source:)
        FileUtils.mkdir_p(docs_dir)
        File.write(File.join(docs_dir, "#{stem}-invalid.md"), invalid_doc(class_name:, source_path:, gate:, reason:, source:))
        raise Error, "loader draft for #{source_path} failed gate #{gate} for #{NAMESPACE}::#{class_name}: #{reason}"
      end

      private def review_doc(raw, source_path, loader_path)
        <<~MARKDOWN
          # Candidate loader: #{raw.fetch(:class_name)}

          Drafted for: `#{source_path}`
          Confidence: #{raw.fetch(:confidence)}

          ## Field mapping

          #{raw.fetch(:field_mapping_explanation)}

          ## Status

          **Not registered.** This draft is inert data in the quarantine at
          `#{File.dirname(loader_path)}/` — nothing requires, loads or
          registers it. To promote it after review: run `ruby -c` on
          `#{loader_path}`, copy it to
          `#{File.join(PROMOTION_DIR, "#{underscore(raw.fetch(:class_name))}.rb")}`,
          add its mirrored spec, and register it in `SFL::Ingest::DeterministicRules`.
        MARKDOWN
      end

      private def invalid_doc(class_name:, source_path:, gate:, reason:, source:)
        <<~MARKDOWN
          # Invalid loader draft: #{class_name}

          Drafted for: `#{source_path}`

          ## Status

          **INVALID — do not promote.** Gate #{gate} rejected this draft:
          #{reason}. No candidate .rb was written anywhere; the raw rejected
          source below is exactly what the predictor produced.

          ## Rejected source

          ````ruby
          #{source}
          ````
        MARKDOWN
      end

      private def underscore(class_name) = class_name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
