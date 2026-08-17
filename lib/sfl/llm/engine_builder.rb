# frozen_string_literal: true

module SFL
  module LLM
    # Composes a per-task Config + LMFactory into a ready-to-use Engine,
    # resolving :pass_two_annotation and :pass_two_batch_annotation to
    # independently-configured LMs (track decision 8).
    class EngineBuilder
      def self.call(
        config:,
        lm_factory: LMFactory.new(config:),
        breaker: Core::Ports::Null::Breaker.new,
        instrumenter: Core::Ports::Null::Instrumenter.new,
        logger: Core::Ports::Null::Logger.new
      )
        Engine.new(
          clause_annotator: Annotators::ClauseAnnotator.new(lm: lm_factory.for(:pass_two_annotation)),
          batch_clause_annotator: Annotators::BatchClauseAnnotator.new(
            lm: lm_factory.for(:pass_two_batch_annotation)
          ),
          breaker:,
          instrumenter:,
          logger:
        )
      end
    end
  end
end
