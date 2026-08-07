# frozen_string_literal: true

require "dotenv"
require "ruby_llm"

module SFL
  # Composition root (track decision 4): the ONLY place in this codebase
  # that reads ENV, and only at call time — every other class takes its
  # config as injected constructor arguments (confirm by skimming
  # LLM::Config, LLM::TaskConfig, LLM::Tracing.configure,
  # Store::Database.connect: all take explicit args; Database.connect's
  # `url ||= ENV.fetch("DATABASE_URL")` fallback exists but Boot always
  # passes `url` explicitly, so that fallback is dead code in practice).
  #
  # Replaces legacy's Compiler::Bootstrap.call against v2's actual
  # collaborators. Three structural differences from legacy, each
  # explained at the point it matters below:
  #
  # 1. Per-task LLM config (track decision 8) instead of one global
  #    DSPY_PROVIDER/model — see TASK_NAMES and #task_config_from_env.
  # 2. No auto-migration (track decision 5) — #connect_db only connects +
  #    installs extensions; `rake db:migrate` is the only place
  #    migrations run.
  # 3. No global PYTHON/PYTHONPATH ENV mutation — Pass 1 is a subprocess
  #    sidecar (track decision 2), not an in-process PyCall require, so
  #    there is no require-time hazard to pre-empt the way legacy's
  #    `configure_vendored_python` had to.
  #
  # Not ported at all: SafeOpenAIClientProxy/SafeChatProxy/
  # SafeCompletionsProxy (DSPy-adapter-specific, moot), apply_request_timeout/
  # apply_generation_params (superseded by TaskConfig#params +
  # ChatFactory#apply_params), configure_jobs/Gush/Sidekiq wiring (Phase 5,
  # not this phase), the global yajl/json_gem require-time patch (nothing
  # in v2 does this).
  # rubocop:disable Metrics/ModuleLength -- a composition root's job is fanning out to every
  # collaborator it wires (LLM::Config, ChatFactory, Embedder, Tracing, Database,
  # SpacySidecarParser's command:) plus per-step ENV documentation; splitting further than the
  # per-concern private methods already here would scatter one conceptual "boot the app" unit
  # across files with no natural seams (Result/Error/LangfuseReachability already got their own
  # files precisely because they ARE separable concerns — this is what's left after that split).
  module Boot
    # Every task name any `chat_factory.for(:...)`/`config.for(:...)` call
    # site in this codebase currently uses (grepped, not guessed):
    # EngineBuilder resolves :pass_two_annotation/:pass_two_batch_annotation,
    # LLM::Config's own doc comment names :embedding and :context_synthesis
    # as the other two members of the per-task map. If a future call site
    # adds a fifth task, add its name here — Config.for raises a clear
    # LLM::Error for anything unregistered, so a missed entry fails loudly
    # rather than silently falling back to nothing.
    TASK_NAMES = %i[
      pass_two_annotation
      pass_two_batch_annotation
      context_synthesis
      embedding
      ingest_classification
      loader_drafting
    ].freeze

    # Default provider/model for the two Pass 2 tasks, carried over from
    # legacy's single DSPY_PROVIDER default
    # ("openrouter/mistralai/mistral-small-3.2-24b-instruct" in this repo's
    # own .env) split into TaskConfig's separate provider:/model: fields
    # (no more "provider/model" string to prefix-parse — track decision 8
    # made TaskConfig#provider a plain Symbol already).
    DEFAULT_PROVIDER = :openrouter
    DEFAULT_MODEL = "mistralai/mistral-small-3.2-24b-instruct"

    # :context_synthesis has no legacy equivalent (it's new in v2) — rather
    # than invent an unrelated default, its own default provider/model
    # (unless SFL_TASK_CONTEXT_SYNTHESIS_* overrides it) is whatever
    # :pass_two_annotation resolved to, on the theory that "the same model
    # already trusted for Pass 2 annotation" is a more defensible starting
    # point than a second invented default. See #build_llm_config.

    # :embedding's default model mirrors legacy's Compiler::Embedder
    # default ("embeddinggemma:latest") and reuses the EMBEDDING_MODEL env
    # var this repo's .env already sets, as a fallback layer beneath the
    # new SFL_TASK_EMBEDDING_MODEL var (see #build_llm_config).
    DEFAULT_EMBEDDING_PROVIDER = :ollama
    DEFAULT_EMBEDDING_MODEL = "embeddinggemma:latest"

    # ENV var per provider whose absence is a hard Boot::Error — mirrors
    # legacy's KEY_ENV_BY_PREFIX, but keyed by the plain provider Symbol
    # TaskConfig#provider already holds (RubyLLM registers providers as
    # :openai/:openrouter/:anthropic/:gemini/:mistral/:ollama, among
    # others — verified against the installed ruby_llm 1.16.0's
    # `RubyLLM::Provider.register` calls in lib/ruby_llm.rb; note :gemini,
    # not legacy's "google/" prefix naming, though the ENV var name itself
    # stays GOOGLE_API_KEY to match this repo's existing .env). :ollama is
    # deliberately absent — its `configuration_requirements` is
    # `[:ollama_api_base]` only (verified against
    # Providers::Ollama.configuration_requirements), no API key, so there
    # is nothing to validate/set here for it; LLM::Embedder already
    # configures ollama_api_base globally (RubyLLM.config is a process
    # singleton) from its own injected `ollama_base_url:`, and that
    # config is built unconditionally whenever require_llm: true — so
    # :ollama already works as a primary chat/annotation provider too,
    # with no further wiring needed here.
    REQUIRED_KEY_ENV_BY_PROVIDER = {
      openrouter: "OPENROUTER_API_KEY",
      gemini: "GOOGLE_API_KEY",
      openai: "OPENAI_API_KEY",
      anthropic: "ANTHROPIC_API_KEY",
      mistral: "MISTRAL_API_KEY",
    }.freeze

    # RubyLLM.configure setter name per provider — verified against each
    # provider class's `configuration_options` in the installed ruby_llm
    # 1.16.0 source (lib/ruby_llm/providers/{openai,anthropic,gemini,
    # openrouter,mistral}.rb). RubyLLM's config is a process-global
    # singleton (RubyLLM.config ||= Configuration.new) — even though
    # ChatFactory's `chat_builder:` seam lets specs stub RubyLLM.chat
    # directly, a real RubyLLM::Chat still reads its provider's
    # credentials from this global config, so Boot must set it once, same
    # spirit as legacy's RUBY_LLM_KEY_SETTER table.
    RUBY_LLM_KEY_SETTER = {
      openrouter: :openrouter_api_key=,
      gemini: :gemini_api_key=,
      openai: :openai_api_key=,
      anthropic: :anthropic_api_key=,
      mistral: :mistral_api_key=,
    }.freeze

    DEFAULT_SPACY_MODEL = "en_core_web_sm"
    DEFAULT_OLLAMA_BASE_URL = "http://localhost:11434"
    DEFAULT_EMBEDDING_TIMEOUT_SECONDS = 30.0

    # bin/setup-python (a companion script, provisioned separately) writes
    # the resolved interpreter's absolute path here after vendoring spaCy
    # into APP_ROOT/.sfl-python/python — one line, trailing newline,
    # nothing else. Mirrored from that script's own documented contract
    # (bin/setup-python: APP_ROOT/VENDOR_DIR/INTERPRETER_FILE constants),
    # not re-derived independently.
    APP_ROOT = File.expand_path("../..", __dir__)
    INTERPRETER_PATH_FILE = File.join(APP_ROOT, ".sfl-python", "interpreter_path")

    # bin/setup-python's PYTHON_TARGET_DIR: spaCy is `pip install --target`ed
    # here rather than into the interpreter's own site-packages, so the
    # sidecar subprocess needs PYTHONPATH set to this directory at spawn
    # time (see #resolve_pass1_env) — the interpreter alone isn't enough.
    PYTHON_TARGET_DIR = File.join(APP_ROOT, ".sfl-python", "python")

    # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- one flag per
    # independently-skippable startup concern (mirrors legacy Bootstrap.call's
    # require_db:/require_llm:/require_observability: shape) plus the four DI seams
    # (env:/tty:/input:/ruby_llm:) every ENV-touching or process-global-touching method in this
    # codebase exposes for specs; the body is one flat build-each-Result-field sequence.
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
      input: $stdin,
      ruby_llm: RubyLLM
    )
      Dotenv.load if load_dotenv

      llm_config, chat_factory, embedder, classifier = build_llm_collaborators(env, ruby_llm) if require_llm

      configure_tracing(env, tty:, input:) if require_tracing

      db = require_db ? connect_db(env) : nil

      spacy_model = env["SPACY_MODEL"] || DEFAULT_SPACY_MODEL
      pass1_command = resolve_pass1_command(spacy_model)
      pass1_env = pass1_command ? { "PYTHONPATH" => PYTHON_TARGET_DIR } : nil
      api_debug_errors = env["SFL_API_DEBUG_ERRORS"] == "true"
      api_cors_origins = resolve_api_cors_origins(env)

      Result.new(db:, llm_config:, chat_factory:, embedder:, classifier:, pass1_command:, pass1_env:, spacy_model:,
        api_debug_errors:, api_cors_origins:)
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

    module_function def build_llm_collaborators(env, ruby_llm)
      llm_config = build_llm_config(env)
      validate_api_keys!(llm_config, env)
      configure_ruby_llm_providers(llm_config, env, ruby_llm)

      # chat_builder: routes through the injected ruby_llm seam, not ChatFactory's own hardcoded
      # ::RubyLLM default — Boot is now the first caller that builds a chat eagerly (for
      # `classifier` below) rather than lazily inside a later command, so it must honor the same
      # "specs never touch the real ::RubyLLM" seam every other ENV/process-global-touching
      # method in this module already does.
      chat_factory = LLM::ChatFactory.new(
        config: llm_config, chat_builder: -> (model:, provider:) { ruby_llm.chat(model:, provider:) }
      )
      embedder = build_embedder(llm_config, env, ruby_llm)
      # Eagerly resolving :ingest_classification's chat here (unlike embedder, whose model/
      # provider strings aren't touched until an actual #embed call) means a misconfigured
      # ingest_classification model/provider fails Boot.call for every require_llm: true caller,
      # not just ingest commands. Deliberate, not a laziness regression: matches
      # validate_api_keys! above, which already fails boot for ANY misconfigured task's provider
      # key regardless of whether the current command uses that task — "fail fast on any task
      # misconfiguration at boot" is this module's established risk model, not something new here.
      classifier = LLM::Classifier.new(chat: chat_factory.for(:ingest_classification))

      [llm_config, chat_factory, embedder, classifier]
    end

    # ENV convention for per-task config (track decision 8), decided here
    # since Phase 1's card explicitly deferred "full ENV-driven resolution"
    # to this Boot work: for each task in TASK_NAMES, an uppercased
    # `SFL_TASK_<TASK_NAME>_MODEL` / `_PROVIDER` / `_TEMPERATURE` triple.
    # `_PROVIDER`, if set, must be one of RubyLLM's registered provider
    # symbols (:openai/:openrouter/:anthropic/:gemini/:ollama). Only
    # `temperature` gets a dedicated ENV var — TaskConfig#params is a free
    # Hash for anything else (top_p, top_k, max_tokens, ...), and there is
    # no established v2 convention yet for exposing arbitrary param keys
    # via ENV var names; add one here if/when a task actually needs it,
    # rather than speculatively generalizing now.
    # rubocop:disable Metrics/MethodLength -- six independent per-task TaskConfig builds (two of
    # them, ingest_classification/loader_drafting, needing an explanatory comment on their
    # borrowed default), then one Config.new — no natural sub-grouping to extract without
    # scattering related task-default reasoning across multiple methods.
    module_function def build_llm_config(env)
      pass_two_annotation = pass_two_task_config(:pass_two_annotation, env)
      pass_two_batch_annotation = pass_two_task_config(:pass_two_batch_annotation, env)
      context_synthesis = task_config_from_env(
        :context_synthesis, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )
      embedding = embedding_task_config(env)
      # No existing "cheap chat model" default to borrow from — :embedding's default is the
      # cheapest task already configured, same defensible-starting-point judgment call
      # :context_synthesis makes above by reusing :pass_two_annotation's default.
      ingest_classification = task_config_from_env(
        :ingest_classification, env, default_provider: embedding.provider, default_model: embedding.model
      )
      # No existing "reasoning tier" default either — :pass_two_annotation's default is the
      # strongest general-purpose task already configured.
      loader_drafting = task_config_from_env(
        :loader_drafting, env,
        default_provider: pass_two_annotation.provider, default_model: pass_two_annotation.model
      )

      LLM::Config.new(tasks: {
        pass_two_annotation:,
        pass_two_batch_annotation:,
        context_synthesis:,
        embedding:,
        ingest_classification:,
        loader_drafting:,
      })
    end
    # rubocop:enable Metrics/MethodLength

    module_function def pass_two_task_config(name, env)
      task_config_from_env(name, env, default_provider: DEFAULT_PROVIDER, default_model: DEFAULT_MODEL)
    end

    module_function def embedding_task_config(env)
      task_config_from_env(
        :embedding, env,
        default_provider: DEFAULT_EMBEDDING_PROVIDER, default_model: env["EMBEDDING_MODEL"] || DEFAULT_EMBEDDING_MODEL
      )
    end

    module_function def task_config_from_env(name, env, default_provider:, default_model:)
      prefix = "SFL_TASK_#{name.to_s.upcase}_"
      model = presence(env["#{prefix}MODEL"]) || default_model
      provider = presence(env["#{prefix}PROVIDER"])&.to_sym || default_provider
      temperature = presence(env["#{prefix}TEMPERATURE"])&.to_f
      params = temperature ? { temperature: } : {}

      LLM::TaskConfig.new(model:, provider:, params:)
    end

    # @param env [#[]] environment source
    # @return [Array<String>] SFL_API_CORS_ORIGINS split on commas and trimmed, or
    #   API::Server::DEFAULT_CORS_ORIGINS when unset (issue #35).
    module_function def resolve_api_cors_origins(env)
      raw = presence(env["SFL_API_CORS_ORIGINS"])
      return API::Server::DEFAULT_CORS_ORIGINS unless raw

      raw.split(",").map(&:strip).reject(&:empty?)
    end

    module_function def presence(value)
      return nil if value.nil? || value.strip.empty?

      value
    end

    module_function def providers_in_use(config)
      config.tasks.values.filter_map(&:provider).uniq
    end

    # Per-task provider API keys, not legacy's single api_key_for(provider)
    # — providers can differ per task now (track decision 8), so every
    # distinct provider in use gets checked, not just one.
    module_function def validate_api_keys!(config, env)
      providers_in_use(config).each do |provider|
        key_env = REQUIRED_KEY_ENV_BY_PROVIDER[provider]
        next unless key_env # no key required for this provider (e.g. :ollama)

        key = env[key_env]
        raise Error, "#{key_env} is not set (required for provider #{provider.inspect})" if key.nil? || key.strip.empty?
      end
    end

    # Mirrors legacy's configure_ruby_llm_provider: DSPy no longer exists
    # to mirror credentials into, but a real RubyLLM::Chat still reads
    # from this same global config regardless of how it was built, so it
    # must be set once here regardless.
    module_function def configure_ruby_llm_providers(config, env, ruby_llm)
      ruby_llm.configure do |c|
        providers_in_use(config).each do |provider|
          setter = RUBY_LLM_KEY_SETTER[provider]
          next unless setter

          c.public_send(setter, env.fetch(REQUIRED_KEY_ENV_BY_PROVIDER[provider]))
        end
      end
    end

    module_function def build_embedder(llm_config, env, ruby_llm)
      embedding_task = llm_config.for(:embedding)
      timeout_seconds = (env["SFL_EMBEDDING_TIMEOUT_SECONDS"] || DEFAULT_EMBEDDING_TIMEOUT_SECONDS).to_f

      LLM::Embedder.new(
        model: embedding_task.model,
        provider: embedding_task.provider,
        ollama_base_url: env["OLLAMA_BASE_URL"] || DEFAULT_OLLAMA_BASE_URL,
        breaker: Core::Ports::TimeoutBreaker.new(timeout_seconds:),
        ruby_llm:
      )
    end

    # Straight replacement for legacy's configure_observability, plus the
    # LangfuseReachability preflight legacy's CLI ran separately before
    # `require "sfl-compiler"` — folded into Boot here since v2 has no
    # require-time hazard forcing them apart (see LangfuseReachability's
    # own file comment). :cancel raises rather than legacy CLI's
    # `warn "Cancelled."; exit 1` — Boot is a composition-root library
    # method, not an entry point, and `exit` inside one is generally bad
    # practice (it can't be rescued, complicates testing, and surprises
    # any caller that isn't literally a `bin/` script). The not-yet-built
    # CLI is expected to rescue Boot::Error at its own top level and exit
    # there instead.
    module_function def configure_tracing(env, tty:, input:)
      return unless LangfuseReachability.tracing_requested?(env)

      decision = LangfuseReachability.decide(env:, tty:, input:)
      if decision == :cancel
        raise Error, "Cancelled: Langfuse tracing endpoint unreachable and the operator declined to continue " \
          "without it."
      end
      return if decision == :skip_tracing

      LLM::Tracing.configure(host: env["LANGFUSE_HOST"], public_key: env["LANGFUSE_PUBLIC_KEY"],
        secret_key: env["LANGFUSE_SECRET_KEY"])
    end

    # Deliberately does NOT run migrations (track decision 5, unlike
    # legacy's Bootstrap#connect_db calling Migrator.new(db).run_all) —
    # migrations run only via `rake db:migrate` (see Rakefile), never
    # automatically at boot or per-job.
    module_function def connect_db(env)
      url = env["DATABASE_URL"]
      raise Error, "DATABASE_URL is not set" if url.nil? || url.strip.empty?

      db = Store::Database.connect(url)
      Store::Database.setup_extensions(db)
      db
    rescue Sequel::Error => e
      raise Error, "Database connection failed for #{url}: #{e.message}"
    end

    # Points SpacySidecarParser at bin/setup-python's vendored interpreter
    # when it has been provisioned; returns nil (letting
    # SpacySidecarParser fall back to its own `["python3",
    # DEFAULT_SCRIPT_PATH, "--model", model]` default) when it hasn't. A
    # missing vendor dir is a legitimate "not yet provisioned" state, not
    # a Boot-time failure — the sidecar itself fails loudly if bare
    # `python3` lacks spaCy, which is an acceptable place for that
    # particular failure to surface (SpacySidecarParser's own
    # STARTUP_TIMEOUT_SECONDS/SidecarError machinery already handles it).
    #
    # Reuses SpacySidecarParser::DEFAULT_SCRIPT_PATH rather than
    # recomputing the sidecar script's path independently, so there is
    # only one place that relative-path calculation lives.
    #
    # No global PYTHON/PYTHONPATH ENV mutation (unlike legacy's
    # configure_vendored_python) — that hazard doesn't exist for a
    # subprocess sidecar invoked via an explicit `command:` array.
    module_function def resolve_pass1_command(spacy_model)
      return nil unless File.exist?(INTERPRETER_PATH_FILE)

      interpreter = File.read(INTERPRETER_PATH_FILE).strip
      return nil if interpreter.empty?

      [interpreter, Core::PassOne::SpacySidecarParser::DEFAULT_SCRIPT_PATH, "--model", spacy_model]
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
