# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Combined annotated clause — the full output of the two-pass compiler.
      class AnnotatedClause < Dry::Struct
        attribute :id, Types::String
        attribute :text, Types::String
        attribute :syntactic, SyntacticClause
        attribute :ideational, IdeationalPayload
        attribute :interpersonal, InterpersonalPayload
        attribute :textual, TextualPayload.optional.default(nil)
        attribute :document_id, Types::String.optional
        attribute :compiled_at, Types::Time
        attribute :untrusted, Types::Bool.default(false)
      end
    end
  end
end
