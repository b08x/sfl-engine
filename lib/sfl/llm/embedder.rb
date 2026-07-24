# frozen_string_literal: true

module SFL
  module LLM
    # Ollama-backed Core::Ports::Embedder adapter — the first *real*
    # (non-Null/Fake) Embedder in this codebase; only Null::Embedder
    # (always an empty vector) and Fake::Embedder (deterministic test
    # double) existed before this (see Rakefile's `embeddings:redrive`
    # task, which raised with a TODO pointing at exactly this gap).
    #
    # Ports legacy's Compiler::Embedder
    # (sfl-compiler/lib/sfl/compiler/retrieval/embedder.rb) via
    # RubyLLM.embed(text, model:, provider: :ollama), with two
    # deliberate contract changes:
    #
    # 1. The `circuit_breaker` gem is dropped in favor of this codebase's
    #    own Core::Ports::Breaker port, injected as `breaker:` the same
    #    way LLM::Engine and Retrieval::ContextSynthesizer already do
    #    (D6: "three uncoordinated circuit-breaker mechanisms" was one of
    #    the original audit findings — a third, uncoordinated resilience
    #    mechanism here would repeat exactly that anti-pattern).
    #
    # 2. A failed embed call RAISES (SFL::LLM::Error) instead of legacy's
    #    silent `nil` return. Core::Ports::Embedder's own contract
    #    documents `#embed(text) -> Array<Float>` unconditionally — there
    #    is no sanctioned nil/empty-on-failure case for a caller to check.
    #    A caller that received a swallowed failure as a same-shaped-as-
    #    success `nil`/`[]` and stored it as if it were a real embedding
    #    is exactly the silent-degradation failure mode track decision D9
    #    ("no silent degradation") rules out elsewhere in this codebase
    #    (Engine/ContextSynthesizer degrade to explicit, provenance-
    #    tagged defaults — they never fabricate a value indistinguishable
    #    from a real one). Null::Embedder already exists as the sanctioned
    #    "I explicitly don't want a real embedding" seam — callers that
    #    want that behavior should inject Null::Embedder, not rely on this
    #    class quietly becoming one on failure.
    #
    # Configuration is fully injected (`model:`, `ollama_base_url:`) per
    # track decision 4 — this class never reads ENV itself; SFL::Boot
    # resolves EMBEDDING_MODEL/OLLAMA_BASE_URL and passes them in.
    class Embedder
      include Core::Ports::Embedder

      # @param model [String] e.g. "embeddinggemma:latest"
      # @param ollama_base_url [String] e.g. "http://localhost:11434"
      # @param breaker [#call] Core::Ports::Breaker-compatible
      # @param logger [#debug,#info,#warn,#error] Core::Ports::Logger-compatible
      # @param ruby_llm [Module] injectable seam so specs never touch the real ::RubyLLM
      def initialize(
        model:,
        ollama_base_url:,
        breaker: Core::Ports::Null::Breaker.new,
        logger: Core::Ports::Null::Logger.new,
        ruby_llm: RubyLLM
      )
        @model = model
        @breaker = breaker
        @logger = logger
        @ruby_llm = ruby_llm
        configure_ruby_llm(ollama_base_url)
      end

      # @param text [String]
      # @return [Array<Float>]
      # @raise [ArgumentError] if text is nil/blank
      # @raise [SFL::LLM::Error] if the embedding call fails
      def embed(text)
        raise ArgumentError, "text must not be nil/blank" if text.nil? || text.strip.empty?

        breaker.call("embedder.embed") { fetch(text) }
      rescue ArgumentError
        raise
      rescue => e
        fail_embed("embed", e)
      end

      # @param texts [Array<String>]
      # @return [Array<Array<Float>>] one vector per input text, same order
      # @raise [SFL::LLM::Error] if the embedding call fails
      def embed_batch(texts)
        return [] if texts.empty?

        breaker.call("embedder.embed_batch") { fetch_batch(texts) }
      rescue => e
        fail_embed("embed_batch", e)
      end

      attr_reader :model, :breaker, :logger, :ruby_llm
      private :model, :breaker, :logger, :ruby_llm

      private def configure_ruby_llm(ollama_base_url)
        ruby_llm.configure do |config|
          config.ollama_api_base = openai_compatible_base(ollama_base_url)
          config.default_embedding_model = model
        end
      end

      # RubyLLM::Providers::Ollama subclasses OpenAI and only speaks
      # OpenAI-style routes — verified against the installed ruby_llm
      # 1.16.0 provider source: Ollama#api_base returns
      # `@config.ollama_api_base` with NO fallback suffix (unlike
      # OpenAI#api_base, which defaults to ".../v1" on its own), and
      # OpenAI::Embeddings#embedding_url resolves to the bare relative
      # path "embeddings" against whatever api_base is configured. Without
      # the /v1 suffix here, requests land on bare /embeddings instead of
      # /v1/embeddings, which Ollama's OpenAI-compatible surface doesn't
      # route. This detail still holds in 1.16.0 — not assumed carried
      # over from legacy.
      private def openai_compatible_base(base_url)
        base = base_url.chomp("/")
        base.end_with?("/v1") ? base : "#{base}/v1"
      end

      private def fetch(text)
        response = ruby_llm.embed(text, model:, provider: :ollama)
        response.vectors
      end

      private def fetch_batch(texts)
        response = ruby_llm.embed(texts, model:, provider: :ollama)
        response.vectors
      end

      private def fail_embed(context, error)
        logger.error { "embedder #{context} failed: #{error.class}: #{error.message}" }
        raise Error, "embedder #{context} failed: #{error.message}"
      end
    end
  end
end
