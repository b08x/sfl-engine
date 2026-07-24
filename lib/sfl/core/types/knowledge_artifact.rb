# frozen_string_literal: true

module SFL
  module Core
    module Types
      # A single section of a document assessed for KB cleaning/migration
      # by Analysis::KnowledgeBaseSource — ported from legacy
      # Types::KnowledgeArtifact verbatim (AnnotatedClause/MoodType are
      # this codebase's own, already Zeitwerk-resolved constants).
      class KnowledgeArtifact < Dry::Struct
        attribute :artifact_id,         Types::Integer
        attribute :title,               Types::String
        attribute :source_file,         Types::String
        attribute :section_path,        Types::String.optional.default(nil)
        attribute :content_type,        KBContentType
        attribute :quality_score,       Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :migration_action,    MigrationAction
        attribute :migration_reason,    Types::String.default("")
        attribute :tags,                Types::Array.of(Types::String).default([].freeze)
        attribute :last_updated,        Types::Nominal::Time.optional.default(nil)
        attribute :clauses,             Types::Array.of(AnnotatedClause).default([].freeze)
        attribute :avg_tenor,           Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :avg_modality,        Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :dominant_mood,       Types::MoodType
        attribute :process_types,       Types::Hash.default({}.freeze)
        attribute :annotation_coverage, Types::Hash.default({}.freeze)
      end
    end
  end
end
