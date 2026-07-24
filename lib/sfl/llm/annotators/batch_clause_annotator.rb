# frozen_string_literal: true

module SFL
  module LLM
    module Annotators
      # Calls the LLM once for many clauses' Pass 2 annotations — the
      # batched counterpart to ClauseAnnotator. One call per clause
      # measured far fewer clauses/min than the equivalent batched call in
      # the legacy engine; batching cuts the call count substantially at
      # the cost of a single larger prompt/response.
      class BatchClauseAnnotator
        # @param chat [#with_schema] a RubyLLM::Chat (or compatible double)
        def initialize(chat:)
          @chat = chat
        end

        # @param contexts [Array<Hash>] each a :index plus the same keys ClauseAnnotator
        #   takes — see lib/sfl/prompts/templates/pass_two_batch_annotation.txt.erb
        # @return [Array<Hash>] one Hash per annotation the LLM returned, symbol-keyed,
        #   each carrying the :index it answers — not guaranteed to cover every input
        #   index, and callers must not assume response order matches input order
        def call(contexts)
          prompt = Prompts.render(:pass_two_batch_annotation, clauses: contexts)
          response = chat.with_schema(Schemas::BatchClauseAnnotationSchema).ask(prompt)
          ResponseSymbolizer.call(response.content).fetch(:annotations)
        end

        private

        attr_reader :chat
      end
    end
  end
end
