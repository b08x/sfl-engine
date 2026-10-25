# frozen_string_literal: true

require "dspy/anthropic/lm/model_capabilities"

module SFL
  module LLM
    # Gets the per-task request knobs onto the wire through DSPy's adapters.
    #
    # dspy-openai hardcodes temperature in OpenAIAdapter#chat (1.0 for gpt-5
    # and gpt-4o, 0.0 otherwise), and OpenRouterAdapter takes no temperature:
    # keyword. dspy-anthropic's AnthropicAdapter sends temperature 0.0 for any
    # model its capability table does not list, and models that reject
    # temperature answer 400. A value passed to DSPy::LM.new is therefore never
    # sent, which is why SFL_TASK_*_TEMPERATURE had no effect. install! wraps
    # the adapter's create call so that every request is rewritten after the
    # adapter has built it. The same singleton-method pattern is used by
    # legacy's Bootstrap#apply_request_timeout.
    #
    # Two client shapes are wrapped: the OpenAI-compatible
    # client.chat.completions (create), and the Anthropic client.messages
    # (create and stream). Any other shape fails loudly when pins are needed.
    module RequestPinning
      # The `provider` field makes OpenRouter reject a request rather than
      # silently drop a parameter the chosen endpoint does not support.
      OPENROUTER_PROVIDER = { require_parameters: true }.freeze

      # Anthropic's Messages API takes neither a seed nor a reasoning effort
      # through these pins, so configuring either one for an Anthropic task
      # would be dropped or rejected. Fail at install rather than send a
      # request the operator believes carries it.
      ANTHROPIC_UNSUPPORTED = %i[seed reasoning_effort].freeze

      # Raised when knobs are configured but the adapter's client doesn't
      # expose a shape install! can wrap, or a knob the shape cannot carry is
      # configured. The alternative — returning the LM unpinned — sends
      # requests the operator believes carry temperature/seed/max_tokens when
      # they do not, so a client-shape change must fail here, loudly.
      class Error < SFL::LLM::Error; end

      # Wraps the adapter's create call (and, for Anthropic, stream) so each
      # request carries the pinned params. A no-op when nothing is configured
      # to pin (no knobs and not OpenRouter, not Anthropic); raises Error when
      # pins are configured and the client shape is not one this module knows
      # how to wrap.
      #
      # For provider "anthropic", a task with no temperature key gets
      # omit_temperature, so the adapter's 0.0 is removed. A numeric temperature
      # on a model whose capability reports fixed_sampling is rejected here,
      # because the API answers it with a 400 at request time.
      # @param language_model [DSPy::LM]
      # @param params [Hash] TaskConfig#params (temperature, omit_temperature,
      #   seed, max_tokens, reasoning_effort)
      # @param openrouter [Boolean] whether the provider is OpenRouter
      # @param provider [String, Symbol, nil] the provider name, e.g. "anthropic"
      # @param model [String, nil] the model id as configured, without the provider prefix
      # @return [DSPy::LM] the same language_model
      # @raise [Error] pins are configured but the client shape is unrecognized,
      #   or a numeric temperature is configured for a fixed-sampling Anthropic model
      module_function def install!(language_model, params:, openrouter:, provider: nil, model: nil)
        params = anthropic_params(params, model) if provider.to_s == "anthropic"
        return language_model if params.empty? && !openrouter

        client = language_model.adapter.instance_variable_get(:@client)
        if chat_completions?(client)
          pin_call(client.chat.completions, :create) { |request| apply(request, params:, openrouter:) }
        elsif messages_api?(client)
          pin_messages(client, params)
        else
          raise Error, "cannot pin request params: adapter client #{client.class} " \
            "exposes neither chat.completions nor messages (dspy-openai or " \
            "dspy-anthropic client shape changed?)"
        end
        language_model
      end

      # @param request [Hash] the params the adapter built for one create call
      # @param params [Hash] TaskConfig#params
      # @param openrouter [Boolean]
      # @return [Hash] a new hash; the request is not mutated
      module_function def apply(request, params:, openrouter:)
        pinned = pin_temperature(request.dup, params)
        pinned[:seed] = params[:seed] if params.key?(:seed)
        pinned[:max_tokens] = params[:max_tokens] if params.key?(:max_tokens)

        return pinned unless openrouter

        pin_openrouter(pinned, params)
      end

      # Anthropic counterpart of #apply. Temperature and max_tokens only; the
      # Messages API has no seed, and reasoning is set by the adapter itself.
      # @param request [Hash] the params the Anthropic adapter built
      # @param params [Hash] TaskConfig#params
      # @return [Hash] a new hash; the request is not mutated
      module_function def apply_anthropic(request, params:)
        pinned = pin_temperature(request.dup, params)
        pinned[:max_tokens] = params[:max_tokens] if params.key?(:max_tokens)
        pinned
      end

      module_function def chat_completions?(client)
        client.respond_to?(:chat) && client.chat.respond_to?(:completions)
      end

      module_function def messages_api?(client)
        client.respond_to?(:messages) && client.messages.respond_to?(:create)
      end

      module_function def pin_messages(client, params)
        reject_anthropic_knobs!(params)
        pin_call(client.messages, :create, check: method(:reject_unusable_response!)) do |request|
          apply_anthropic(request, params:)
        end
        pin_call(client.messages, :stream) { |request| apply_anthropic(request, params:) }
      end

      # The adapter reads only text blocks and ignores stop_reason. A refusal
      # returns text cut short, and a response with no text block returns "".
      # Either reaches DSPy's JSON parser, which then reports only the parse
      # failure. Raise here, naming the stop_reason and block types instead.
      # Responses that are not Messages (no stop_reason) pass through.
      # @param response [Object] the value the create call returned
      # @return [Object] response, unchanged, when it carries an answer
      # @raise [Error] when the response is a refusal or has no text or tool_use block
      module_function def reject_unusable_response!(response)
        return response unless response.respond_to?(:stop_reason)

        stop_reason = response.stop_reason.to_s
        blocks = Array(response.content).map { |block| block.type.to_s }
        types = blocks.join(", ")
        raise Error, "Anthropic refused the request (stop_reason refusal, block types #{types}); no answer to parse" if stop_reason == "refusal"
        return response if blocks.intersect?(%w[text tool_use])

        raise Error, "Anthropic returned no text block (stop_reason #{stop_reason}, block types #{types}); no answer to parse"
      end

      # Anthropic task params with the unset-temperature default applied. A
      # task with no temperature key (not a number, not none) omits temperature.
      # @return [Hash] params, possibly with omit_temperature added; the input is not mutated
      module_function def anthropic_params(params, model)
        reject_fixed_sampling!(params, model)
        return params if params.key?(:temperature) || params.key?(:omit_temperature)

        params.merge(omit_temperature: true)
      end

      module_function def reject_anthropic_knobs!(params)
        bad = ANTHROPIC_UNSUPPORTED.select { |knob| params.key?(knob) }
        return if bad.empty?

        raise Error, "cannot pin #{bad.join(', ')} on the Anthropic Messages API; remove it from the task config"
      end

      # A numeric temperature is rejected by models whose capability reports
      # fixed_sampling. An unknown model gets the gem's DEFAULT (not fixed), so
      # it is not rejected here.
      module_function def reject_fixed_sampling!(params, model)
        return unless params.key?(:temperature)
        return unless DSPy::Anthropic::LM::ModelCapabilities.for(model.to_s).fixed_sampling

        raise Error, "#{model} uses fixed sampling and rejects a configured temperature " \
          "(#{params[:temperature]}); set this task's temperature to none"
      end

      # Replaces target.name with a wrapper that transforms the request hash
      # before the original method sees it, and passes the result to check
      # (when given) before returning it. Accepts the positional-hash and
      # keyword call forms the adapters use.
      module_function def pin_call(target, name, check: nil)
        original = target.method(name)
        target.define_singleton_method(name) do |request = nil, **kwargs|
          result = original.call(yield(request || kwargs))
          check&.call(result)
          result
        end
      end

      module_function def pin_temperature(pinned, params)
        if params[:omit_temperature]
          pinned.delete(:temperature)
        elsif params.key?(:temperature)
          pinned[:temperature] = params[:temperature]
        end
        pinned
      end

      module_function def pin_openrouter(pinned, params)
        extra_body = { provider: OPENROUTER_PROVIDER }
        extra_body[:reasoning] = { effort: params[:reasoning_effort] } if params[:reasoning_effort]
        options = pinned.fetch(:request_options, {})
        pinned[:request_options] = options.merge(extra_body: (options[:extra_body] || {}).merge(extra_body))
        pinned
      end

      private_class_method :chat_completions?, :messages_api?, :pin_messages, :anthropic_params,
        :reject_anthropic_knobs!, :reject_fixed_sampling!, :pin_call, :pin_temperature, :pin_openrouter,
        :reject_unusable_response!
    end
  end
end
