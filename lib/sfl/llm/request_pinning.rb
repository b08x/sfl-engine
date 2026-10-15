# frozen_string_literal: true

module SFL
  module LLM
    # Gets the per-task request knobs onto the wire through DSPy's
    # OpenAI-compatible adapters.
    #
    # dspy-openai hardcodes temperature in OpenAIAdapter#chat (1.0 for gpt-5
    # and gpt-4o, 0.0 otherwise), and OpenRouterAdapter takes no temperature:
    # keyword. A value passed to DSPy::LM.new is therefore never sent, which
    # is why SFL_TASK_*_TEMPERATURE had no effect. install! wraps the
    # completions object so that every create call is rewritten after the
    # adapter has built it. The same singleton-method pattern is used by
    # legacy's Bootstrap#apply_request_timeout.
    #
    # Pins are applied only where the adapter's client exposes chat.completions.
    module RequestPinning
      # The `provider` field makes OpenRouter reject a request rather than
      # silently drop a parameter the chosen endpoint does not support.
      OPENROUTER_PROVIDER = { require_parameters: true }.freeze

      # Wraps the adapter's completions#create so each request carries the
      # pinned params. A no-op when the adapter has no chat.completions.
      # @param language_model [DSPy::LM]
      # @param params [Hash] TaskConfig#params (temperature, omit_temperature,
      #   seed, max_tokens, reasoning_effort)
      # @param openrouter [Boolean] whether the provider is OpenRouter
      # @return [DSPy::LM] the same language_model
      module_function def install!(language_model, params:, openrouter:)
        client = language_model.adapter.instance_variable_get(:@client)
        return language_model unless client.respond_to?(:chat) && client.chat.respond_to?(:completions)

        completions = client.chat.completions
        original_create = completions.method(:create)
        completions.define_singleton_method(:create) do |request = nil, **kwargs|
          original_create.call(RequestPinning.apply(request || kwargs, params:, openrouter:))
        end
        language_model
      end

      # @param request [Hash] the params the adapter built for one create call
      # @param params [Hash] TaskConfig#params
      # @param openrouter [Boolean]
      # @return [Hash] a new hash; the request is not mutated
      module_function def apply(request, params:, openrouter:)
        pinned = request.dup

        if params[:omit_temperature]
          pinned.delete(:temperature)
        elsif params.key?(:temperature)
          pinned[:temperature] = params[:temperature]
        end
        pinned[:seed] = params[:seed] if params.key?(:seed)
        pinned[:max_tokens] = params[:max_tokens] if params.key?(:max_tokens)

        return pinned unless openrouter

        extra_body = { provider: OPENROUTER_PROVIDER }
        extra_body[:reasoning] = { effort: params[:reasoning_effort] } if params[:reasoning_effort]
        options = pinned.fetch(:request_options, {})
        pinned[:request_options] = options.merge(extra_body: (options[:extra_body] || {}).merge(extra_body))
        pinned
      end
    end
  end
end
