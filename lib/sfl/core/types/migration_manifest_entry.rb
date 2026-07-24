# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One row in Analysis::KnowledgeBaseSource's migration manifest —
      # stripped of clause payloads. Ported from legacy
      # Types::MigrationManifestEntry verbatim.
      class MigrationManifestEntry < Dry::Struct
        attribute :artifact_id,   Types::Integer
        attribute :title,         Types::String
        attribute :source_file,   Types::String
        attribute :action,        MigrationAction
        attribute :reason,        Types::String
        attribute :quality_score, Types::Float.constrained(gteq: 0.0, lteq: 1.0)
        attribute :content_type,  KBContentType
      end
    end
  end
end
