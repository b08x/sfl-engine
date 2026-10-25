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

    # embedding defaults to :ollama provider and Store::PgEmbeddingStore::DEFAULT_MODEL,
    # overridden by SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL.
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
    MIGRATIONS_DIR = File.join(APP_ROOT, "db", "migrations")

    # BERTopic sidecar: the Python executable (SFL_BERTOPIC_PYTHON) runs this repo's script.
    DEFAULT_BERTOPIC_PYTHON = "python3"
    BERTOPIC_SIDECAR_SCRIPT = File.join(APP_ROOT, "sidecar", "bertopic", "bertopic_sidecar.py")

    # rubocop:disable Metrics/ParameterLists -- each flag controls a distinct
    # startup concern, plus DI seams (env, tty, input, ruby_llm) for testability
    # @param env [#[], #fetch] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @param require_db [Boolean] connect the database (no migrations — see Store::Database)
    # @param require_llm [Boolean] build LLM::Config/ChatFactory/Embedder, validate + set
    #   provider API keys (false for a pass1-only run)
    # @param require_tracing [Boolean] run the Langfuse reachability preflight + configure
    #   tracing when LANGFUSE_* is present in env
    # @param require_schema [Boolean] check the schema is at the latest migration
    #   (see {.ensure_schema_current!}); only with require_db
    # @param tty [Boolean] whether stdin is interactive, for the Langfuse reachability prompt
    # @param input [#gets] injectable stdin for the Langfuse reachability prompt
    # @param ruby_llm [Module] injectable seam so specs never touch the real ::RubyLLM
    # @return [Boot::Result]
    # @raise [Boot::Error] a required provider API key is missing, DATABASE_URL is unset, the
    #   database connection fails, the schema is behind (require_schema), the task_models table cannot be read, or Langfuse tracing is unreachable and the operator declined
    #   to continue without it
    module_function def call(
      env: ENV,
      load_dotenv: true,
      require_db: true,
      require_llm: true,
      require_tracing: true,
      require_schema: false,
      tty: $stdin.tty?,
      input: $stdin
    )
      Dotenv.load if load_dotenv

      db = connect_db_step(env, require_db:, require_schema:)
      model_resolver = build_model_resolver(env, db)

      llm_config, lm_factory, embedder, classifier = build_llm_collaborators(env, model_resolver) if require_llm

      configure_tracing(env, tty:, input:) if require_tracing

      spacy_model = resolve_spacy_model(env)
      pass1_command = resolve_pass1_command(spacy_model)
      pass1_env = pass1_command ? { "PYTHONPATH" => PYTHON_TARGET_DIR } : nil
      api_debug_errors = env["SFL_API_DEBUG_ERRORS"] == "true"
      api_cors_origins = resolve_api_cors_origins(env)
      narrative_variant = resolve_narrative_variant(env)
      embedding_model = resolve_embedding_model(env)
      bertopic_command = resolve_bertopic_command(env)
      topic_speaker_names = resolve_topic_speaker_names(env)
      embedder_info = resolve_embedder_info(llm_config, env)

      Result.new(db:, llm_config:, lm_factory:, embedder:, classifier:, pass1_command:, pass1_env:, spacy_model:,
        api_debug_errors:, api_cors_origins:, narrative_variant:, model_resolver:, embedding_model:,
        bertopic_command:, topic_speaker_names:, embedder_info:)
    end

    # Connects only when require_db; checks the schema after connecting only
    # when require_schema (see {.ensure_schema_current!}).
    module_function def connect_db_step(env, require_db:, require_schema:)
      return nil unless require_db

      db = connect_db(env)
      ensure_schema_current!(db) if db && require_schema
      db
    end

    # The task_models rows are read only when Boot connected to the database.
    module_function def build_model_resolver(env, db)
      TaskModelResolver.new(env:, store: db && Store::PgModelRepository.new(db))
    end

    module_function def resolve_spacy_model(env) = env["SPACY_MODEL"] || DEFAULT_SPACY_MODEL

    module_function def resolve_embedding_model(env) = presence(env["SFL_TASK_EMBEDDING_MODEL"]) || Store::PgEmbeddingStore::DEFAULT_MODEL
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
    #
    # While the foreground dashboard owns the terminal, +screen+ (built with
    # the minimum level) takes the place of the stderr target, and is added
    # even when stderr is not listed, so the dashboard's log panel always has
    # the run's log. journald is unaffected.
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @param journald_socket [String] socket path that must exist for journald
    # @param screen [#call, nil] level (Integer) -> Core::Ports::Logger, the dashboard's log
    # @return [Core::Ports::Logger]
    # @raise [Error] on an unknown target or level, or a missing journald socket
    module_function def logger(env: ENV, load_dotenv: true, journald_socket: JOURNALD_SOCKET, screen: nil)
      Dotenv.load if load_dotenv
      targets = resolve_log_targets(env)
      level = resolve_log_level(env)
      loggers = build_loggers(targets, level, run_id(env:, load_dotenv: false), journald_socket, screen)
      loggers.one? ? loggers.first : Core::Ports::MultiLogger.new(loggers)
    end

    module_function def resolve_log_level(env)
      level = env["SFL_LOG_LEVEL"].to_s.empty? ? "info" : env["SFL_LOG_LEVEL"].downcase
      raise Error, "SFL_LOG_LEVEL must be one of #{LOG_LEVELS.keys.join(', ')} (got #{level.inspect})" unless LOG_LEVELS.key?(level)

      level
    end

    # One logger per target; +screen+, when given, replaces stderr.
    module_function def build_loggers(targets, level, id, journald_socket, screen)
      targets -= ["stderr"] if screen
      loggers = targets.map { |target| build_log_target(target, level, id, journald_socket) }
      loggers << screen.call(LOG_LEVELS.fetch(level)) if screen
      loggers
    end

    # DATABASE_URL for tasks that connect without the rest of Boot (rake db:migrate).
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [String]
    # @raise [Error] when DATABASE_URL is unset
    module_function def database_url(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      presence(env["DATABASE_URL"]) || raise(Error, "DATABASE_URL is not set")
    end

    # RACK_ENV for the Roda app in app/, default "development". Read without .env.
    # @param env [#[]] environment source, injectable for tests
    # @return [String]
    module_function def rack_environment(env: ENV) = presence(env["RACK_ENV"]) || "development"

    # Settings for the Roda app in app/ (read through app/config/config.rb).
    # Outside production, .env is loaded first, SESSION_SECRET falls back to a
    # random per-process secret and DATABASE_URL to a local app_<env> database.
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first outside production (off in tests)
    # @return [Hash] `{secret:, environment:, db: {url:}}`
    # @raise [Error] in production when SESSION_SECRET or DATABASE_URL is unset
    module_function def web_settings(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv && rack_environment(env:) != "production"
      environment = rack_environment(env:)
      production = environment == "production"
      { secret: session_secret(env, production:), environment:, db: { url: web_database_url(env, environment) } }
    end

    module_function def session_secret(env, production:)
      secret = presence(env["SESSION_SECRET"])
      return secret if secret
      raise Error, "SESSION_SECRET is not set (required when RACK_ENV=production)" if production

      @session_secret ||= SecureRandom.hex(64)
    end

    module_function def web_database_url(env, environment)
      return database_url(env:, load_dotenv: false) if environment == "production" || presence(env["DATABASE_URL"])

      "postgres://user:password@localhost:5432/app_#{environment}"
    end

    # SFL_AUTO_START_DOCKER=1 lets exe/sfl-analyze and exe/sfl-tui start
    # docker compose. Read before Boot.call, without .env (see DockerServices).
    # @param env [#[]] environment source, injectable for tests
    # @return [Boolean]
    module_function def auto_start_docker?(env: ENV) = env["SFL_AUTO_START_DOCKER"] == "1"

    # SFL_SKIP_LLM_BOOT=true makes the rack boot (boot.rb) skip LLM wiring.
    # @param env [#[]] environment source, injectable for tests
    # @return [Boolean]
    module_function def skip_llm_boot?(env: ENV) = env["SFL_SKIP_LLM_BOOT"] == "true"

    # SFL_ENABLE_TRACING=true makes the rack boot (boot.rb) configure Langfuse tracing.
    # @param env [#[]] environment source, injectable for tests
    # @return [Boolean]
    module_function def tracing_enabled?(env: ENV) = env["SFL_ENABLE_TRACING"] == "true"

    # Where exe/sfl-api binds: HOST (default 0.0.0.0) and PORT (default 3001).
    # @param env [#fetch] environment source, injectable for tests
    # @return [Hash] `{host:, port:}`
    module_function def api_bind(env: ENV) = { host: env.fetch("HOST", "0.0.0.0"), port: env.fetch("PORT", "3001") }

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

    DEFAULT_EDITOR = "vi"
    DEFAULT_EXPORT_DIR = "./output/exports"
    DEFAULT_INGEST_LOG_DIR = "./output/logs"

    # Settings for sfl-tui: the reviewer name review decisions are recorded
    # under, the editor command for editing review text, the export
    # directory, the launcher's log directory and the kitty variables.
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [Boot::TerminalSettings]
    module_function def terminal_settings(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      TerminalSettings.new(
        reviewer: presence(env["SFL_REVIEWER_NAME"]&.strip),
        editor: resolve_editor(env),
        export_dir: presence(env["SFL_EXPORT_DIR"]) || DEFAULT_EXPORT_DIR,
        ingest_log_dir: presence(env["SFL_INGEST_LOG_DIR"]) || DEFAULT_INGEST_LOG_DIR,
        kitty_window_id: presence(env["KITTY_WINDOW_ID"]),
        kitty_listen_on: presence(env["KITTY_LISTEN_ON"])
      )
    end

    module_function def resolve_editor(env) = presence(env["VISUAL"]) || presence(env["EDITOR"]) || DEFAULT_EDITOR

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

    module_function def build_llm_collaborators(env, model_resolver = TaskModelResolver.new(env:))
      llm_config = model_resolver.call
      validate_api_keys!(llm_config, env)

      lm_factory = LLM::LMFactory.new(config: llm_config, env:)
      embedder = build_embedder(llm_config, env)
      classifier = LLM::Classifier.new(lm: lm_factory.for(:ingest_classification))

      [llm_config, lm_factory, embedder, classifier]
    end

    # Per-task LLM configuration: SFL_TASK_<TASK_NAME>_{MODEL,PROVIDER,...}
    # env vars, then the `task_models` rows in +store+, then the defaults
    # (Boot::TaskModelResolver).
    # @param store [Core::Ports::ModelStore, nil]
    # @return [LLM::Config]
    module_function def build_llm_config(env, store: nil) = TaskModelResolver.new(env:, store:).call

    # The model listings `rake models:refresh` and the Models tab read: the
    # ruby_llm registry, Ollama at OLLAMA_BASE_URL and OpenRouter (with
    # OPENROUTER_API_KEY when set).
    # @param env [#[]] environment source, injectable for tests
    # @param load_dotenv [Boolean] read .env first (off in tests)
    # @return [Array<Core::Ports::ModelCatalog>]
    module_function def model_catalogs(env: ENV, load_dotenv: true)
      Dotenv.load if load_dotenv
      [
        LLM::Catalogs::RubyLLMCatalog.new,
        LLM::Catalogs::OllamaCatalog.new(base_url: presence(env["OLLAMA_BASE_URL"]) || DEFAULT_OLLAMA_BASE_URL),
        LLM::Catalogs::OpenRouterCatalog.new(api_key: presence(env["OPENROUTER_API_KEY"])),
      ]
    end

    # Every knob is optional. TEMPERATURE=none and REASONING_EFFORT=none mean
    # "do not send this param": some models (gpt-5.6-luna-pro) reject
    # temperature, and omitting reasoning lets the endpoint choose.
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

    # Fails when the database is not at the latest migration in db/migrations
    # (resolved from the project root, not the cwd). The migrator creates an
    # empty schema_info table when there is none, as `rake db:migrate` would.
    # @param db [Sequel::Database]
    # @param directory [String] the integer migrations directory
    # @return [void]
    # @raise [SchemaError] naming the database, its version and the latest version
    module_function def ensure_schema_current!(db, directory: MIGRATIONS_DIR)
      Sequel.extension :migration
      return if Sequel::Migrator.is_current?(db, directory)

      migrator = Sequel::IntegerMigrator.new(db, directory)
      raise SchemaError, "database #{db.opts[:database]} is at schema version #{migrator.current}, " \
        "latest is #{migrator.target}; run `bundle exec rake db:migrate`"
    rescue Sequel::Error => e
      raise SchemaError, "schema check failed for database #{db.opts[:database]}: #{e.message}"
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

    # argv that starts the BERTopic sidecar: SFL_BERTOPIC_PYTHON (default python3) and this repo's script.
    module_function def resolve_bertopic_command(env)
      [presence(env["SFL_BERTOPIC_PYTHON"]) || DEFAULT_BERTOPIC_PYTHON, BERTOPIC_SIDECAR_SCRIPT]
    end

    # SFL_BERTOPIC_SPEAKER_NAMES, comma-separated; the TopicInputCleaner strips these labels before embedding.
    module_function def resolve_topic_speaker_names(env)
      env.fetch("SFL_BERTOPIC_SPEAKER_NAMES", "").split(",").map(&:strip).reject(&:empty?)
    end

    # Provider, model and (for ollama) endpoint of the embedding task, named in TopicModeler's probe errors.
    # nil when require_llm: false, because no embedding task is built then.
    module_function def resolve_embedder_info(llm_config, env)
      return nil unless llm_config

      task = llm_config.for(:embedding)
      info = { provider: task.provider.to_s, model: task.model.to_s }
      info[:endpoint] = env["OLLAMA_BASE_URL"] || DEFAULT_OLLAMA_BASE_URL if task.provider.to_s == "ollama"
      info
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
