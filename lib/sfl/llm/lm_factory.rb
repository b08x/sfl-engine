# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    # Builds a DSPy::LM for a given task name, resolving its
    # {provider, model, params} from an injected Config (track decision 8).
    class LMFactory
      # @param env [#[]] provider API keys, passed by Boot
      def initialize(config:, env:)
        @config = config
        @env = env
      end

      # @param task [Symbol] e.g. :pass_two_annotation
      # @return [DSPy::LM]
      def for(task)
        task_config = config.for(task)

        provider_name = task_config.provider&.to_s || "ollama"
        api_key = key_for(provider_name)

        # dspy requires "<provider>/<model>"
        identifier = "#{provider_name}/#{task_config.model}"

        kwargs = {}
        kwargs[:api_key] = api_key if api_key

        # temperature is not passed here: the adapter hardcodes its own value
        # and OpenRouterAdapter rejects the keyword. RequestPinning rewrites each
        # request instead. Installed even with no knobs, because the OpenRouter
        # provider pin must reach every request, and an Anthropic task with no
        # temperature needs its adapter default removed.
        RequestPinning.install!(DSPy::LM.new(identifier, **kwargs),
          params: task_config.params, openrouter: provider_name == "openrouter",
          provider: provider_name, model: task_config.model)
      end

      # The task's provider, model and API key as plain values, for callers
      # that talk to the provider without DSPy. Builds no DSPy object.
      #
      # @param task [Symbol] e.g. :narrative_generation
      # @return [Hash] provider: String, model: String, api_key: String or nil
      #   (nil when the environment holds no key for the provider), api_base:
      #   String or nil (nil for every provider but ollama)
      def credentials_for(task)
        task_config = config.for(task)
        provider_name = task_config.provider&.to_s || "ollama"
        {
          provider: provider_name,
          model: task_config.model,
          api_key: key_for(provider_name),
          api_base: base_for(provider_name),
        }
      end

      attr_reader :config, :env

      # RubyLLM's Ollama provider posts to "<api_base>/chat/completions", Ollama's
      # OpenAI-compatible route under /v1; OLLAMA_BASE_URL names the bare host.
      private def base_for(provider_name)
        return nil unless provider_name == "ollama"

        host = env["OLLAMA_BASE_URL"].to_s.strip
        host = Boot::DEFAULT_OLLAMA_BASE_URL if host.empty?
        host = host.chomp("/")
        host.end_with?("/v1") ? host : "#{host}/v1"
      end

      private def key_for(provider_name)
        case provider_name
        when "openrouter" then env["OPENROUTER_API_KEY"]
        when "openai" then env["OPENAI_API_KEY"]
        when "anthropic" then env["ANTHROPIC_API_KEY"]
        when "gemini" then env["GOOGLE_API_KEY"]
        when "mistral" then env["MISTRAL_API_KEY"]
        else nil
        end
      end
    end
  end
end
