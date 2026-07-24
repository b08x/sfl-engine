# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Pass 2 port: produces interpersonal annotations for syntactic
      # clauses via an LLM. `annotate_batch` exists as a distinct method
      # (not just a loop over `annotate`) because the ruby_llm engine's
      # batch schema is a genuinely different call shape/cost profile, not
      # an implementation detail to hide.
      module Annotator
        # @param clause [SFL::Core::Types::SyntacticClause]
        # @param context [Hash] additional context (e.g. preceding turns)
        # @return [SFL::Core::Types::InterpersonalPayload]
        def annotate(clause, context: {})
          raise NotImplementedError, "#{self.class} must implement #annotate"
        end

        # @param clauses [Array<SFL::Core::Types::SyntacticClause>]
        # @param context [Hash]
        # @return [Array<SFL::Core::Types::InterpersonalPayload>]
        def annotate_batch(clauses, context: {})
          raise NotImplementedError, "#{self.class} must implement #annotate_batch"
        end
      end
    end
  end
end
