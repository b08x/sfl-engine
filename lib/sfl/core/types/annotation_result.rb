# frozen_string_literal: true

module SFL
  module Core
    module Types
      # Combined output of one Ports::Annotator#annotate call: the
      # interpersonal and textual metafunction payloads an LLM (or any
      # Annotator implementation) produces together from a single clause.
      class AnnotationResult < Dry::Struct
        attribute :interpersonal, InterpersonalPayload
        attribute :textual, TextualPayload.optional.default(nil)
      end
    end
  end
end
