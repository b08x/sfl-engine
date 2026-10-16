# frozen_string_literal: true

require "dotenv"
require "securerandom"
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

    # Langfuse REST client for the evaluation harness (datasets, scores, queues).
    # Separate from {.call} because eval tasks need no database or LLM wiring.
    # @param env [#[], #fetch] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [Eval::LangfuseClient]
    # @raise [Error] when the host or either key is missing
    module_function def langfuse_client(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      host = env["LANGFUSE_HOST"] || env["LANGFUSE_BASE_URL"]
      public_key = env["LANGFUSE_PUBLIC_KEY"]
      secret_key = env["LANGFUSE_SECRET_KEY"]
      missing = {
        "LANGFUSE_HOST" => host,
        "LANGFUSE_PUBLIC_KEY" => public_key,
        "LANGFUSE_SECRET_KEY" => secret_key,
      }.select { |_, value| value.to_s.empty? }.keys
      raise Error, "Langfuse client needs #{missing.join(', ')}" if missing.any?

      Eval::LangfuseClient.new(host:, public_key:, secret_key:, logger: logger(env:, load_dotenv: false))
    end

    LOG_TARGETS = %w[stderr journald].freeze
    LOG_LEVELS = { "debug" => 0, "info" => 1, "warn" => 2, "error" => 3, "fatal" => 4 }.freeze
    JOURNALD_LEVELS = { "debug" => 7, "info" => 6, "warn" => 4, "error" => 3, "fatal" => 2 }.freeze

    JOURNALD_SOCKET = "/run/systemd/journal/socket"

    # Logger for the CLI and API. SFL_LOG_TARGET is a comma list of stderr
    # (default) and journald; each log call goes to every listed target.
    # SFL_LOG_LEVEL picks the minimum severity (default info). Every line is
    # tagged with {.run_id}.
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @param journald_socket [String] socket path that must exist for journald
    # @return [Core::Ports::Logger]
    # @raise [Error] on an unknown target or level, or a missing journald socket
    module_function def logger(env: ENV, load_dotenv: true, journald_socket: JOURNALD_SOCKET)
      Dotenv.load if load_dotenv
      targets = resolve_log_targets(env)
      level = env["SFL_LOG_LEVEL"].to_s.empty? ? "info" : env["SFL_LOG_LEVEL"].downcase
      raise Error, "SFL_LOG_LEVEL must be one of #{LOG_LEVELS.keys.join(', ')} (got #{level.inspect})" unless LOG_LEVELS.key?(level)

      id = run_id(env:, load_dotenv: false)
      loggers = targets.map { |target| build_log_target(target, level, id, journald_socket) }
      loggers.one? ? loggers.first : Core::Ports::MultiLogger.new(loggers)
    end

    # Run id stamped on every log line: SFL_RUN_ID when set, else a fresh UUID.
    # Generated once per process and memoized only when generated, so a set
    # SFL_RUN_ID is always honoured at call time.
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [String]
    module_function def run_id(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      presence(env["SFL_RUN_ID"]) || (@generated_run_id ||= SecureRandom.uuid)
    end

    module_function def resolve_log_targets(env)
      raw = env["SFL_LOG_TARGET"].to_s
      targets = raw.split(",").map(&:strip).reject(&:empty?).uniq
      targets = ["stderr"] if targets.empty?
      unknown = targets - LOG_TARGETS
      return targets if unknown.empty?

      raise Error, "SFL_LOG_TARGET must be a comma list of #{LOG_TARGETS.join(', ')} (got #{raw.inspect})"
    end

    module_function def build_log_target(target, level, id, journald_socket)
      if target == "journald"
        raise Error, "SFL_LOG_TARGET lists journald but its socket is missing: #{journald_socket}" unless File.socket?(journald_socket)

        Core::Ports::JournaldLogger.new(level: JOURNALD_LEVELS.fetch(level), tags: { sfl_run_id: id })
      else
        Core::Ports::StderrLogger.new(level: LOG_LEVELS.fetch(level), run_id: id)
      end
    end

    # Paths of the four raw exports that `rake eval:run_unseen` expands into
    # unseen conversations. Each can be overridden with an SFL_EVAL_* variable;
    # the ChatGPT value may be a glob because its export directory is dated.
    # @param workspace [String] directory holding the Datasets/ folder
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [Hash{Symbol => String}] :claude, :chatgpt, :mistral, :notebooklm
    module_function def eval_sources(workspace:, env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      defaults = {
        claude: ["SFL_EVAL_CLAUDE_EXPORT", "#{workspace}/Datasets/ClaudeExports/2026-09-27/conversations-000/conversations.json"],
        chatgpt: ["SFL_EVAL_CHATGPT_EXPORT", "#{workspace}/Datasets/ChatGPTexport/*/conversations-003.json"],
        mistral: [
          "SFL_EVAL_MISTRAL_EXPORT",
          "#{workspace}/Datasets/MistralLeChatExports/2026-10-01/chat-export-1790856293990/" \
            "chat-aca44f91-4a8f-4233-a1e9-ab72c3b6b95f.json",
],
        notebooklm: [
          "SFL_EVAL_NOTEBOOKLM_FILE",
          File.expand_path("~/NotebookLM/The Disruption of Existential Anchors_assets/" \
            "artifacts/The_Real_AI_Threat_Is_Human_Paranoia_nlp.jsonl"),
],
      }
      defaults.transform_values do |(name, default)|
        value = env[name]
        value.to_s.empty? ? default : value
      end
    end

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
