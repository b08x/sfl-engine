# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Pass 2 port: produces interpersonal+textual annotations for
      # syntactic clauses via an LLM. Takes `ideational` as its own
      # argument (not buried in `context`) because every real
      # implementation needs it — it's Pass 1's own output, not optional
      # extra context. `annotate_batch` exists as a distinct method (not
      # just a loop over `annotate`) because the ruby_llm engine's batch
      # schema is a genuinely different call shape/cost profile, not an
      # implementation detail to hide.
      module Annotator
        # @param clause [SFL::Core::Types::SyntacticClause]
        # @param ideational [SFL::Core::Types::IdeationalPayload]
        # @param context [Hash] optional extra context (e.g. semantic_coherence_score)
        # @return [SFL::Core::Types::AnnotationResult]
        def annotate(clause, ideational, context: {})
          raise NotImplementedError, "#{self.class} must implement #annotate"
        end

        # @param pairs [Array<[SFL::Core::Types::SyntacticClause, SFL::Core::Types::IdeationalPayload]>]
        # @param context [Hash]
        # @return [Array<SFL::Core::Types::AnnotationResult>] same order as pairs
        def annotate_batch(pairs, context: {})
          raise NotImplementedError, "#{self.class} must implement #annotate_batch"
        end
      end
    end
  end
end
