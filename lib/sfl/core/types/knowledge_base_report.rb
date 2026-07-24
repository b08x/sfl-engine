# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Full report produced by Analysis::KnowledgeBaseSource#analyze.
      # Structurally distinct from AnalysisResult (turns/tenor_timeline/
      # key_moments/speaker_profiles) by design — a knowledge base is a
      # files-to-sections walk, not conversation turns. Ported from legacy
      # Types::KnowledgeBaseReport verbatim.
      class KnowledgeBaseReport < Dry::Struct
        attribute :metadata,                   Types::Hash
        attribute :artifacts,                  Types::Array.of(KnowledgeArtifact).default([].freeze)
        attribute :migration_manifest,         Types::Array.of(MigrationManifestEntry).default([].freeze)
        attribute :content_type_distribution,  Types::Hash.default({}.freeze)
        attribute :quality_distribution,       Types::Hash.default({}.freeze)
        attribute :staleness_flags,            Types::Array.of(Types::Hash).default([].freeze)
      end
    end
  end
end
