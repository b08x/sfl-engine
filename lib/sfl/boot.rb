# frozen_string_literal: true

require "dotenv"
require "dspy"

module SFL
  # Composition root: the ONLY place in this codebase that reads ENV (at call
  # time only). All other classes receive their config via injected constructor
  # arguments.
  #
  # Key differences from legacy:
  # - Per-task LLM config instead of global DSPY_PROVIDER/model
  # - No auto-migration: #connect_db only connects + installs extensions
  # - Pass 1 runs as a subprocess sidecar, avoiding require-time Python hazards
  #
  # rubocop:disable Metrics/ModuleLength -- composition root wires many collaborators;
  # splitting would scatter related logic across files without natural seams
  module Boot
    # All task names used by chat_factory.for(:...) or config.for(:...) calls.
    # If adding a new task, add its name here — Config.for raises LLM::Error
    # for unregistered tasks, ensuring missed entries fail loudly.
    TASK_NAMES = %i[
      pass_two_annotation
      pass_two_batch_annotation
      context_synthesis
      narrative_generation
      embedding
      ingest_classification
      loader_drafting
    ].freeze

    # Default provider for Pass 2 tasks, carried over from legacy's DSPY_PROVIDER.
    DEFAULT_PROVIDER = :openrouter

    # context_synthesis defaults to pass_two_annotation's provider/model when not
    # explicitly configured, as it's a trusted starting point.

    # embedding defaults to :ollama provider, with model from EMBEDDING_MODEL env var
    # (or SFL_TASK_EMBEDDING_MODEL as override).
    DEFAULT_EMBEDDING_PROVIDER = :ollama

    # ENV var names for providers that require API keys. :ollama is excluded
    # as it only requires ollama_api_base (no API key), configured separately.
    REQUIRED_KEY_ENV_BY_PROVIDER = {
      openrouter: "OPENROUTER_API_KEY",
      gemini: "GOOGLE_API_KEY",
      openai: "OPENAI_API_KEY",
      anthropic: "ANTHROPIC_API_KEY",
      mistral: "MISTRAL_API_KEY",
    }.freeze

    DEFAULT_SPACY_MODEL = "en_core_web_sm"
    DEFAULT_OLLAMA_BASE_URL = "http://tinybot:11434"
    DEFAULT_EMBEDDING_TIMEOUT_SECONDS = 30.0

    # Paths for the vendored Python environment (provisioned by bin/setup-python).
    # spaCy is installed via `pip install --target` to PYTHON_TARGET_DIR, so
    # the sidecar subprocess needs PYTHONPATH set to this directory.
    APP_ROOT = File.expand_path("../..", __dir__)
    INTERPRETER_PATH_FILE = File.join(APP_ROOT, ".sfl-python", "interpreter_path")
    PYTHON_TARGET_DIR = File.join(APP_ROOT, ".sfl-python", "python")

    # rubocop:disable Metrics/ParameterLists -- each flag controls a distinct
    # startup concern, plus DI seams (env, tty, input, ruby_llm) for testability
    # @param env [#[], #fetch] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @param require_db [Boolean] connect the database (no migrations — see Store::Database)
    # @param require_llm [Boolean] build LLM::Config/ChatFactory/Embedder, validate + set
    #   provider API keys (false for a pass1-only run)
    # @param require_tracing [Boolean] run the Langfuse reachability preflight + configure
    #   tracing when LANGFUSE_* is present in env
    # @param tty [Boolean] whether stdin is interactive, for the Langfuse reachability prompt
    # @param input [#gets] injectable stdin for the Langfuse reachability prompt
    # @param ruby_llm [Module] injectable seam so specs never touch the real ::RubyLLM
    # @return [Boot::Result]
    # @raise [Boot::Error] a required provider API key is missing, DATABASE_URL is unset, the
    #   database connection fails, or Langfuse tracing is unreachable and the operator declined
    #   to continue without it
    module_function def call(
      env: ENV,
      load_dotenv: true,
      require_db: true,
      require_llm: true,
      require_tracing: true,
      tty: $stdin.tty?,
      input: $stdin
    )
      Dotenv.load if load_dotenv

      llm_config, lm_factory, embedder, classifier = build_llm_collaborators(env) if require_llm

      configure_tracing(env, tty:, input:) if require_tracing

      db = require_db ? connect_db(env) : nil

      spacy_model = env["SPACY_MODEL"] || DEFAULT_SPACY_MODEL
      pass1_command = resolve_pass1_command(spacy_model)
      pass1_env = pass1_command ? { "PYTHONPATH" => PYTHON_TARGET_DIR } : nil
      api_debug_errors = env["SFL_API_DEBUG_ERRORS"] == "true"
      api_cors_origins = resolve_api_cors_origins(env)
      narrative_variant = resolve_narrative_variant(env)

      Result.new(db:, llm_config:, lm_factory:, embedder:, classifier:, pass1_command:, pass1_env:, spacy_model:,
        api_debug_errors:, api_cors_origins:, narrative_variant:)
    end
    # rubocop:enable Metrics/ParameterLists

    module_function def build_llm_collaborators(env)
      llm_config = build_llm_config(env)
      validate_api_keys!(llm_config, env)

      lm_factory = LLM::LMFactory.new(config: llm_config, env:)
      embedder = build_embedder(llm_config, env)
      classifier = LLM::Classifier.new(lm: lm_factory.for(:ingest_classification))

      [llm_config, lm_factory, embedder, classifier]
    end

    # Build per-task LLM configuration from ENV. Each task can be configured
    # via SFL_TASK_<TASK_NAME>_{MODEL,PROVIDER,TEMPERATURE} environment variables.
    # Tasks without explicit defaults borrow from related tasks (see below).
    module_function def build_llm_config(env)
      pass_two_annotation = pass_two_task_config(:pass_two_annotation, env)
      pass_two_batch_annotation = pass_two_task_config(:pass_two_batch_annotation, env)
      context_synthesis = task_config_from_env(
        :context_synthesis, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )
      # narrative_generation is the narrator for --narrative reports. It defaults to
      # context_synthesis, so an unconfigured install behaves as before, and it can be
      # set separately with SFL_TASK_NARRATIVE_GENERATION_*.
      narrative_generation = task_config_from_env(
        :narrative_generation, env,
        default_provider: context_synthesis.provider, default_model: context_synthesis.model
      )
      embedding = embedding_task_config(env)
      # ingest_classification borrows defaults from embedding (cheapest configured task)
      ingest_classification = task_config_from_env(
        :ingest_classification, env, default_provider: embedding.provider, default_model: embedding.model
      )
      # loader_drafting borrows defaults from pass_two_annotation (strongest general-purpose task)
      loader_drafting = task_config_from_env(
        :loader_drafting, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )

      LLM::Config.new(tasks: {
        pass_two_annotation:,
        pass_two_batch_annotation:,
        context_synthesis:,
        narrative_generation:,
        embedding:,
        ingest_classification:,
        loader_drafting:,
      })
    end
    module_function def pass_two_task_config(name, env)
      task_config_from_env(name, env, default_provider: DEFAULT_PROVIDER, default_model: nil)
    end

    module_function def embedding_task_config(env)
      task_config_from_env(
        :embedding, env,
        default_provider: DEFAULT_EMBEDDING_PROVIDER, default_model: env["EMBEDDING_MODEL"]
      )
    end

    # Every knob is optional. TEMPERATURE=none and REASONING_EFFORT=none mean
    # "do not send this param": some models (gpt-5.6-luna-pro) reject
    # temperature, and omitting reasoning lets the endpoint choose.
    module_function def task_config_from_env(name, env, default_provider:, default_model:)
      prefix = "SFL_TASK_#{name.to_s.upcase}_"
      model = presence(env["#{prefix}MODEL"]) || default_model
      provider = presence(env["#{prefix}PROVIDER"])&.to_sym || default_provider

      LLM::TaskConfig.new(model:, provider:, params: task_params_from_env(prefix, env))
    end

    module_function def task_params_from_env(prefix, env)
      params = {}

      temperature = presence(env["#{prefix}TEMPERATURE"])
      if temperature&.strip&.casecmp?("none")
        params[:omit_temperature] = true
      elsif temperature
        params[:temperature] = temperature.to_f
      end

      seed = presence(env["#{prefix}SEED"])
      params[:seed] = env_integer("#{prefix}SEED", seed) if seed
      max_tokens = presence(env["#{prefix}MAX_TOKENS"])
      params[:max_tokens] = env_integer("#{prefix}MAX_TOKENS", max_tokens) if max_tokens

      effort = presence(env["#{prefix}REASONING_EFFORT"])
      params[:reasoning_effort] = effort.strip if effort && !effort.strip.casecmp?("none")

      params
    end

    # Parses an integer ENV var, failing at startup with the variable's name
    # rather than a bare "invalid value for Integer()" that doesn't say which
    # knob to fix.
    module_function def env_integer(var, raw)
      Integer(raw, 10)
    rescue ArgumentError, TypeError
      raise Error, "#{var} must be an integer (got #{raw.inspect})"
    end

    # @param env [#[]] environment source
    # @return [Array<String>] SFL_API_CORS_ORIGINS split on commas and trimmed, or
    #   empty array when unset (issue #35).
    module_function def resolve_api_cors_origins(env)
      raw = presence(env["SFL_API_CORS_ORIGINS"])
      return [] unless raw

      raw.split(",").map(&:strip).reject(&:empty?)
    end

    # SFL_NARRATIVE_VARIANT selects the narrator signature: v0, v1 or v2. Unset
    # means v1. An unknown value raises here, so a typo fails at startup rather
    # than partway through a run.
    module_function def resolve_narrative_variant(env)
      raw = presence(env["SFL_NARRATIVE_VARIANT"]) || "v1"
      variant = raw.strip.downcase.to_sym
      return variant if LLM::Narrators::NarrativeGenerator::SIGNATURES.key?(variant)

      raise Error, "SFL_NARRATIVE_VARIANT must be one of v0, v1, v2 (got #{raw.inspect})"
    end

    module_function def presence(value)
      return nil if value.nil? || value.strip.empty?

      value
    end

    module_function def providers_in_use(config)
      config.tasks.values.filter_map(&:provider).uniq
    end

    # Validate that all required API keys are present for the configured providers.
    # Unlike legacy, providers can differ per task, so all distinct providers are checked.
    module_function def validate_api_keys!(config, env)
      providers_in_use(config).each do |provider|
        key_env = REQUIRED_KEY_ENV_BY_PROVIDER[provider]
        next unless key_env # no key required for this provider (e.g. :ollama)

        key = env[key_env]
        raise Error, "#{key_env} is not set (required for provider #{provider.inspect})" if key.nil? || key.strip.empty?
      end
    end

    module_function def build_embedder(llm_config, env)
      embedding_task = llm_config.for(:embedding)
      timeout_seconds = (env["SFL_EMBEDDING_TIMEOUT_SECONDS"] || DEFAULT_EMBEDDING_TIMEOUT_SECONDS).to_f

      LLM::Embedder.new(
        model: embedding_task.model,
        provider: embedding_task.provider,
        ollama_base_url: env["OLLAMA_BASE_URL"] || DEFAULT_OLLAMA_BASE_URL,
        breaker: Core::Ports::TimeoutBreaker.new(timeout_seconds:)
      )
    end

    # Configure Langfuse tracing if requested. Performs a reachability check first.
    # Raises Boot::Error on cancellation (caller should rescue and exit appropriately).
    module_function def configure_tracing(env, tty:, input:)
      LangfuseReachability.normalize_host!(env)
      return unless LangfuseReachability.tracing_requested?(env)

      decision = LangfuseReachability.decide(env:, tty:, input:)
      if decision == :cancel
        raise Error,
          "Cancelled: Langfuse tracing endpoint unreachable and the operator declined to continue without it."
      end
      return if decision == :skip_tracing

      LLM::Tracing.configure(
        host: env["LANGFUSE_HOST"],
        public_key: env["LANGFUSE_PUBLIC_KEY"],
        secret_key: env["LANGFUSE_SECRET_KEY"]
      )
    end

    # Connect to the database and set up extensions. Does NOT run migrations;
    # migrations must be run explicitly via `rake db:migrate`.
    module_function def connect_db(env)
      url = env["DATABASE_URL"]
      raise Error, "DATABASE_URL is not set" if url.nil? || url.strip.empty?

      db = Store::Database.connect(url)
      Store::Database.setup_extensions(db)
      db
    rescue Sequel::Error => e
      raise Error, "Database connection failed for #{url}: #{e.message}"
    end

    # Resolve the Pass 1 (spaCy sidecar) command. Returns nil if the vendored
    # Python interpreter hasn't been provisioned yet (SpacySidecarParser will
    # fall back to its default command). The sidecar itself fails loudly if
    # spaCy is missing, which is the appropriate place for that error.
    #
    # Uses SpacySidecarParser::DEFAULT_SCRIPT_PATH to avoid duplicating path logic.
    module_function def resolve_pass1_command(spacy_model)
      return nil unless File.exist?(INTERPRETER_PATH_FILE)

      interpreter = File.read(INTERPRETER_PATH_FILE).strip
      return nil if interpreter.empty?

      [interpreter, Core::PassOne::SpacySidecarParser::DEFAULT_SCRIPT_PATH, "--model", spacy_model]
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
