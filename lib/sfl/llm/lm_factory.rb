# frozen_string_literal: true

require "dspy"

module SFL
  module LLM
    # Builds a DSPy::LM for a given task name, resolving its
    # {provider, model, params} from an injected Config (track decision 8).
    class LMFactory
      def initialize(config:, env: ENV)
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
        kwargs[:temperature] = task_config.params[:temperature] if task_config.params.key?(:temperature)

        DSPy::LM.new(identifier, **kwargs)
      end

      attr_reader :config, :env

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
