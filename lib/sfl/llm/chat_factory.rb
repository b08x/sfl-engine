# frozen_string_literal: true

module SFL
  module LLM
    # Builds a RubyLLM::Chat for a given task name, resolving its
    # {provider, model, params} from an injected Config (track decision 8)
    # instead of any hardcoded per-annotator model constant. `chat_builder`
    # is injectable so specs never construct a real RubyLLM::Chat.
    #
    # Param application is deliberately a two-case fold, not a generic
    # method_missing/send dispatch on param keys (D6: no reflection-as-API)
    # — `temperature` gets RubyLLM::Chat's dedicated `with_temperature`,
    # everything else passes through the one general escape hatch RubyLLM
    # itself provides, `with_params`, verified against the installed
    # ruby_llm 1.16.0 (RubyLLM::Chat has no with_max_output_tokens etc. in
    # this version — only with_model/with_temperature/with_thinking/
    # with_context/with_params/with_headers/with_schema/with_tools/
    # with_instructions).
    class ChatFactory
      def initialize(config:, chat_builder: -> (model:, provider:) { RubyLLM.chat(model:, provider:) })
        @config = config
        @chat_builder = chat_builder
      end

      # @param task [Symbol] e.g. :pass_two_annotation, :embedding
      # @return [RubyLLM::Chat]
      def for(task)
        task_config = config.for(task)
        chat = chat_builder.call(model: task_config.model, provider: task_config.provider)
        apply_params(chat, task_config.params)
      end

      attr_reader :config, :chat_builder
      private :config, :chat_builder

      private def apply_params(chat, params)
        return chat if params.empty?

        chat = chat.with_temperature(params[:temperature]) if params.key?(:temperature)
        rest = params.except(:temperature)
        chat = chat.with_params(**rest) unless rest.empty?
        chat
      end
    end
  end
end
