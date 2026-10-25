# frozen_string_literal: true

require "ruby_llm"

module SFL
  module LLM
    module Narrators
      # Calls the LLM to write the six-section interpretive narrative —
      # the `narrator:` duck Analysis::NarrativeGenerator requires.
      #
      # The request goes through RubyLLM, not DSPy. The provider, model and
      # API key are plain values the CLI passes in (LMFactory#credentials_for
      # on the :narrative_generation TaskConfig); no DSPy object is built or
      # read. The sections
      # are parsed from headed text by SectionParser, so no JSON is requested
      # or prefilled.
      class NarrativeGenerator
        # The model refused (stop_reason "refusal"). Subclasses
        # Analysis::NarrativeError so NarrativeGenerator#generate re-raises it
        # unchanged instead of wrapping it, and the CLI rescues it by name.
        class RefusedError < Analysis::NarrativeError; end

        # The response carries no text.
        class EmptyResponseError < Analysis::NarrativeError; end

        # The configured provider is unknown to RubyLLM, RubyLLM has no API
        # key setting for it, or the task config sets a parameter RubyLLM
        # cannot apply on a chat. Inside the analysis error family so the CLI
        # logs a warning instead of aborting the run.
        class ConfigurationError < Analysis::NarrativeError; end

        SIGNATURES = {
          v0: Signatures::NarrativeSignatureV0,
          v1: Signatures::NarrativeSignatureV1,
          v2: Signatures::NarrativeSignatureV2,
        }.freeze
        DEFAULT_VARIANT = :v1

        # TaskConfig#params keys RubyLLM 2.1.1's Chat has no provider-neutral
        # setter for. A configured one raises ConfigurationError instead of
        # being dropped.
        UNSUPPORTED_PARAMS = %i[seed].freeze

        # @param provider [String, Symbol] RubyLLM provider name
        # @param model [String] model id, sent as configured
        # @param api_key [String, nil] nil leaves the key to RubyLLM's own configuration
        # @param api_base [String, nil] provider API base URL, set on the per-call
        #   context when RubyLLM has a base URL setting for the provider; nil
        #   leaves it to RubyLLM's own configuration
        # @param variant [Symbol] :v0 (one-line baseline), :v1 (sfl-compiler's
        #   signature) or :v2 (V1 plus grounding rules). Selected by
        #   SFL_NARRATIVE_VARIANT; see SFL::Boot. Its description becomes the
        #   system instruction.
        # @param params [Hash] TaskConfig#params. :temperature, :max_tokens and
        #   :reasoning_effort (as the thinking effort) are applied, each only
        #   when set; :seed raises ConfigurationError at #call.
        # @param logger [Core::Ports::Logger] structured log sink
        # @raise [ArgumentError] for an unknown variant
        # rubocop:disable Metrics/ParameterLists -- keyword-only signature pinned by the caller's CONTRACT;
        # LMFactory#credentials_for splats provider/model/api_key/api_base into it.
        def initialize(provider:, model:, api_key:, api_base: nil, variant: DEFAULT_VARIANT, params: {},
          logger: Core::Ports::Null::Logger.new
        )
          @signature = SIGNATURES.fetch(variant) { raise ArgumentError, "unknown narrative variant #{variant.inspect}" }
          @variant = variant
          @provider = provider
          @model = model
          @api_key = api_key
          @api_base = api_base
          @params = params
          @logger = logger
        end
        # rubocop:enable Metrics/ParameterLists

        # @param digest_text [String] Analysis::NarrativeGenerator::Digest#to_text
        # @return [Hash] symbol-keyed, one String entry per
        #   Analysis::NarrativeGenerator::SECTION_KEYS
        # @raise [RefusedError] the provider refused the request
        # @raise [EmptyResponseError] the response carries no text
        # @raise [SectionParser::MissingSectionsError] a required section is absent or empty
        # @raise [ConfigurationError] RubyLLM has no such provider, no API key setting
        #   for it, or the params set an unsupported parameter (see UNSUPPORTED_PARAMS)
        def call(digest_text)
          provider = ruby_llm_provider
          reject_unsupported_params!
          model = @model
          logger.info("narrative request", provider:, model:, variant: @variant, digest_chars: digest_text.length)
          response = build_chat(provider, model).ask(digest_text)
          reject_unusable!(response)
          sections = SectionParser.call(response.content)
          logger.info("narrative generated", provider:, model:, finish_reason: response.finish_reason,
            content_chars: response.content.to_s.length)
          sections
        end

        private attr_reader :logger

        # @return [Symbol] the configured provider as a RubyLLM provider key
        # @raise [ConfigurationError] when RubyLLM has no provider with that name
        private def ruby_llm_provider
          provider = @provider.to_sym
          return provider if RubyLLM::Provider.providers.key?(provider)

          raise ConfigurationError, "RubyLLM has no provider #{provider.inspect} for the narrative task"
        end

        # @raise [ConfigurationError] when the params set a key RubyLLM cannot apply
        private def reject_unsupported_params!
          unsupported = UNSUPPORTED_PARAMS.reject { |key| @params[key].nil? }
          return if unsupported.empty?

          raise ConfigurationError, "RubyLLM cannot apply #{unsupported.join(', ')} to the narrative chat; unset it"
        end

        # One conversation per narrative. Credentials and the API base go into
        # a per-call RubyLLM context, so the process-wide RubyLLM configuration
        # is untouched.
        private def build_chat(provider, model)
          context = RubyLLM.context do |config|
            apply_credential(config, provider)
            apply_api_base(config, provider)
          end
          chat = context.chat(model:, provider:, assume_model_exists: true)
          chat.with_instructions(instructions)
          apply_params(chat)
          chat
        end

        private def apply_params(chat)
          chat.with_temperature(@params[:temperature]) unless @params[:temperature].nil?
          chat.with_max_output_tokens(@params[:max_tokens]) unless @params[:max_tokens].nil?
          chat.with_thinking(effort: @params[:reasoning_effort]) unless @params[:reasoning_effort].nil?
        end

        private def apply_credential(config, provider)
          return if @api_key.nil?

          setter = :"#{provider}_api_key="
          raise ConfigurationError, "RubyLLM has no api key setting for provider #{provider.inspect}" unless config.respond_to?(setter)

          config.public_send(setter, @api_key)
        end

        private def apply_api_base(config, provider)
          setter = :"#{provider}_api_base="
          config.public_send(setter, @api_base) if !@api_base.nil? && config.respond_to?(setter)
        end

        private def instructions
          outline = SectionParser::SECTIONS.map { |_key, (heading, intent)| "- ## #{heading}: #{intent}" }.join("\n")
          "#{@signature.description}\n\n" \
            "Write exactly these six sections, in this order. Begin each one with its heading line " \
            "(for example \"## Overview\"), and write nothing before the first heading:\n#{outline}"
        end

        # The API stops on a refusal and can return no text block; both reach
        # the caller as named errors that carry the stop reason and content shape.
        private def reject_unusable!(response)
          if response.content_filtered? || provider_stop_reason(response) == "refusal"
            raise RefusedError, "narrator refused the request (stop_reason #{stop_reason(response)}, " \
              "#{content_shape(response)}); no answer to parse"
          end
          return unless response.content.to_s.strip.empty?

          raise EmptyResponseError, "narrator returned no text (stop_reason #{stop_reason(response)}, " \
            "#{content_shape(response)})"
        end

        private def stop_reason(response)
          raw = provider_stop_reason(response)
          raw ? "#{response.finish_reason.inspect} / provider #{raw}" : response.finish_reason.inspect
        end

        private def content_shape(response)
          blocks = Array(raw_body(response)&.fetch("content", nil)).map { |block| block.is_a?(Hash) ? block["type"].to_s : "?" }
          "content_chars #{response.content.to_s.length}, block types [#{blocks.join(', ')}]"
        end

        private def provider_stop_reason(response)
          raw_body(response)&.fetch("stop_reason", nil)
        end

        private def raw_body(response)
          body = response.raw.body if response.raw.respond_to?(:body)
          body.is_a?(Hash) ? body : nil
        end
      end
    end
  end
end
