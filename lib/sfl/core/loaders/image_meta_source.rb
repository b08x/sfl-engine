# frozen_string_literal: true

require "time"
require "yaml"

module SFL
  module Core
    module Loaders
      # Normalizes an image-analysis sidecar (image-*.meta.yaml under
      # ~/Notebook/Daily/assets) into exactly one Types::Unit: one file is
      # one document, its single section the "description" an
      # image-analysis pass produced. Replaces the
      # yaml_document_analysis_loader.rb draft from 4a53727, correcting its
      # mapping as approved: attribution lives in metadata ("model_used" /
      # "evaluation"), never in a fabricated "System" speaker, and sent_at
      # comes from the file's "timestamp" — nil with a single warning when
      # it is absent or unparseable, never a fabricated wall-clock value.
      #
      # Security (STRIDE elevation of privilege): the file is parsed with
      # YAML.safe_load only — nothing beyond Time is permitted, so an
      # unquoted YAML timestamp still deserializes — which means a
      # !ruby/object tag is rejected before any Ruby object it names is
      # instantiated. File content names data, never code to run.
      #
      # Fatal cases (unparseable YAML, a non-mapping root, a missing/blank/
      # non-string description, a non-.yaml ref) raise Loaders::Error for
      # the ingest boundary to rescue; the one degraded case (a bad
      # timestamp) warns on stderr and still emits the unit.
      class ImageMetaSource
        include Source

        # Bare YAML timestamp scalars deserialize to Time; permitting it
        # matches MarkdownSource's frontmatter precedent and keeps quoted
        # and unquoted timestamp spellings equivalent.
        PERMITTED_YAML_CLASSES = [Time].freeze

        # @param ref [SFL::Core::Refs::FileRef] an image-*.meta.yaml ref
        # @param file_id [String, nil] section id prefix; defaults to FileId.call(ref)
        def initialize(ref, file_id: nil)
          @ref = ref
          @file_id = file_id || FileId.call(ref)
        end

        # @yield [Types::Unit] the one section the sidecar describes
        # @return [Enumerator] when no block is given
        def each_unit
          return to_enum(:each_unit) unless block_given?

          data = mapping
          yield Types::Unit.new(
            section_id: "#{@file_id}#meta",
            text: description_from(data),
            document_key: @ref.path_hint,
            source_path: @ref.path_hint,
            sent_at: timestamp_from(data),
            metadata: metadata_from(data)
          )
        end

        # Analysis::Engine's optional review hook (see
        # Analysis::ConversationSource for the pattern): a document-analysis
        # sidecar is not a speech turn, so there is no entry to contribute.
        def review_entry(unit:, clauses:) # rubocop:disable Lint/UnusedMethodArgument -- shared Source duck contract
          nil
        end

        # Analysis::Engine's optional metadata hook: the sidecar's fields
        # already ride on each unit's own metadata.
        def extra_metadata(_turns) = {}

        private def mapping
          raise Loaders::Error, unsupported_extension_message unless yaml?

          begin
            parsed = YAML.safe_load(@ref.read, permitted_classes: PERMITTED_YAML_CLASSES)
          rescue Psych::Exception => e
            raise Loaders::Error, "Cannot safely parse #{file_name}: #{e.message}"
          end

          raise Loaders::Error, "Image meta root is not a mapping in #{file_name}" unless parsed.is_a?(Hash)

          parsed
        end

        private def description_from(data)
          description = data["description"]
          raise Loaders::Error, "Invalid description in #{file_name}: expected a non-blank string" unless description.is_a?(String) && !description.strip.empty?

          description
        end

        private def timestamp_from(data)
          value = data["timestamp"]
          return nil if value.nil?
          return value if value.is_a?(Time)

          Time.parse(value.to_s)
        rescue ArgumentError, TypeError
          warn "[WARN] unparseable timestamp #{value.inspect} in #{file_name}: sent_at left nil"
          nil
        end

        private def metadata_from(data)
          metadata = { "file_id" => @file_id }
          metadata["model_used"] = data["model_used"] unless data["model_used"].nil?
          metadata["evaluation"] = data["evaluation"] unless data["evaluation"].nil?
          metadata
        end

        private def unsupported_extension_message
          "Unsupported image meta format #{file_name}: expected a .yaml ref"
        end

        private def yaml? = @ref.extension.casecmp(".yaml").zero?

        private def file_name = "#{@ref.name}#{@ref.extension}"
      end
    end
  end
end
