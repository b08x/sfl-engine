# frozen_string_literal: true

module SFL
  module LLM
    # Composes a per-task Config + ChatFactory into a ready-to-use Engine,
    # resolving :pass_two_annotation and :pass_two_batch_annotation to
    # independently-configured chats (track decision 8) — Engine's own
    # chat: shortcut builds both annotators from the SAME chat, which is
    # exactly what per-task config exists to avoid.
    class EngineBuilder
      def self.call(
        config:,
        chat_factory: ChatFactory.new(config:),
        breaker: Core::Ports::Null::Breaker.new,
        instrumenter: Core::Ports::Null::Instrumenter.new,
        logger: Core::Ports::Null::Logger.new
      )
        Engine.new(
          clause_annotator: Annotators::ClauseAnnotator.new(chat: chat_factory.for(:pass_two_annotation)),
          batch_clause_annotator: Annotators::BatchClauseAnnotator.new(
            chat: chat_factory.for(:pass_two_batch_annotation)
          ),
          breaker:,
          instrumenter:,
          logger:
        )
      end
    end
  end
end
