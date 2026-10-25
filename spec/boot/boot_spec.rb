# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"
require "stringio"

RSpec.describe SFL::Boot do
  let(:base_env) do
    {
      "DATABASE_URL" => "postgresql:///irrelevant-for-these-examples",
      "OPENROUTER_API_KEY" => "or-key",
      "SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "openrouter/gemini-pro",
      "SFL_TASK_PASS_TWO_BATCH_ANNOTATION_MODEL" => "openrouter/gemini-pro",
    }
  end

  # Every example here passes require_db: false, load_dotenv: false, require_tracing: false
  # unless a spec is specifically exercising that concern — this is the unit-level slice the
  # task calls for ("ENV-parsing/Config-building logic ... unit-tested without touching
  # Postgres"); DB connection itself is covered separately below against a real Postgres, the
  # same opt-in pattern spec/support/store_test_db.rb already establishes for spec/store.
  def boot(env:, **overrides)
    described_class.call(
      env:, load_dotenv: false, require_db: false, require_tracing: false,
      **overrides
    )
  end

  describe "ENV loading" do
    it "loads .env via Dotenv when load_dotenv: true" do
      allow(Dotenv).to receive(:load)

      described_class.call(env: base_env, load_dotenv: true, require_db: false, require_tracing: false)

      expect(Dotenv).to have_received(:load)
    end

    it "does not touch Dotenv when load_dotenv: false" do
      allow(Dotenv).to receive(:load)

      boot(env: base_env)

      expect(Dotenv).not_to have_received(:load)
    end
  end

  describe "per-task LLM config (require_llm: true, the default)" do
    it "defaults context_synthesis to whatever pass_two_annotation resolved to" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "openrouter/some-model",
        "SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER" => "openrouter")

      result = boot(env:)

      expect(result.llm_config.for(:context_synthesis).model).to eq("openrouter/some-model")
      expect(result.llm_config.for(:context_synthesis).provider).to eq(:openrouter)
    end

    it "gives narrative_generation its own task, defaulting to context_synthesis when unconfigured" do
      result = boot(env: base_env.merge("SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "openrouter/synth-model"))

      expect(result.llm_config.for(:narrative_generation).model).to eq("openrouter/synth-model")
    end

    it "selects the narrative variant from SFL_NARRATIVE_VARIANT, defaulting to v1 (fact 9)" do
      expect(boot(env: base_env).narrative_variant).to eq(:v1)
      expect(boot(env: base_env.merge("SFL_NARRATIVE_VARIANT" => "v2")).narrative_variant).to eq(:v2)
      expect(boot(env: base_env.merge("SFL_NARRATIVE_VARIANT" => "V0")).narrative_variant).to eq(:v0)
    end

    it "fails at startup on an unknown SFL_NARRATIVE_VARIANT" do
      expect { boot(env: base_env.merge("SFL_NARRATIVE_VARIANT" => "v7")) }
        .to raise_error(SFL::Boot::Error, /SFL_NARRATIVE_VARIANT must be one of v0, v1, v2/)
    end

    it "lets SFL_TASK_NARRATIVE_GENERATION_* override the narrator without touching context_synthesis" do
      env = base_env.merge(
        "SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "openrouter/synth-model",
        "SFL_TASK_NARRATIVE_GENERATION_MODEL" => "openrouter/narrator-model"
      )

      result = boot(env:)

      expect(result.llm_config.for(:narrative_generation).model).to eq("openrouter/narrator-model")
      expect(result.llm_config.for(:context_synthesis).model).to eq("openrouter/synth-model")
    end

    it "lets SFL_TASK_CONTEXT_SYNTHESIS_* override the context_synthesis default" do
      env = base_env.merge("SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "openrouter/different-model",
        "ANTHROPIC_API_KEY" => "anthropic-key")

      result = boot(env:)

      expect(result.llm_config.for(:context_synthesis).model).to eq("openrouter/different-model")
    end

    it "takes the embedding model from SFL_TASK_EMBEDDING_MODEL over the store default" do
      result = boot(env: base_env.merge("SFL_TASK_EMBEDDING_MODEL" => "new-var-model"))

      expect(result.llm_config.for(:embedding).model).to eq("new-var-model")
    end

    it "ignores the legacy EMBEDDING_MODEL and EMBEDDING_PROVIDER names" do
      env = base_env.merge("EMBEDDING_MODEL" => "legacy-var-model", "EMBEDDING_PROVIDER" => "mistral")

      result = boot(env:)

      expect(result.llm_config.for(:embedding)).to have_attributes(provider: :ollama, model: "embeddinggemma-2:440m")
    end

    it "applies SFL_TASK_<NAME>_TEMPERATURE as a params[:temperature]" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_TEMPERATURE" => "0.3")

      result = boot(env:)

      expect(result.llm_config.for(:pass_two_annotation).params).to eq(temperature: 0.3)
    end

    it "reads SEED, MAX_TOKENS and REASONING_EFFORT into params, as the request knobs (fact 6)" do
      env = base_env.merge(
        "SFL_TASK_PASS_TWO_ANNOTATION_SEED" => "42",
        "SFL_TASK_PASS_TWO_ANNOTATION_MAX_TOKENS" => "2048",
        "SFL_TASK_PASS_TWO_ANNOTATION_REASONING_EFFORT" => "low"
      )

      result = boot(env:)

      expect(result.llm_config.for(:pass_two_annotation).params).to eq(seed: 42, max_tokens: 2048, reasoning_effort: "low")
    end

    it "fails at startup naming the ENV var when SEED is not an integer" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_SEED" => "four")

      expect { boot(env:) }.to raise_error(SFL::Boot::Error, /SFL_TASK_PASS_TWO_ANNOTATION_SEED must be an integer/)
    end

    it "fails at startup naming the ENV var when MAX_TOKENS is not an integer" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_MAX_TOKENS" => "2_048x")

      expect { boot(env:) }.to raise_error(SFL::Boot::Error, /SFL_TASK_PASS_TWO_ANNOTATION_MAX_TOKENS must be an integer/)
    end

    it "treats TEMPERATURE=none as omit_temperature, not as 0.0 (fact 6)" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_TEMPERATURE" => "none")

      result = boot(env:)

      expect(result.llm_config.for(:pass_two_annotation).params).to eq(omit_temperature: true)
    end

    it "treats REASONING_EFFORT=none as no reasoning param at all" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_REASONING_EFFORT" => "none")

      result = boot(env:)

      expect(result.llm_config.for(:pass_two_annotation).params).to eq({})
    end

    it "builds a real Embedder wired to OLLAMA_BASE_URL/the resolved embedding model" do
      env = base_env.merge("OLLAMA_BASE_URL" => "http://tinybot:11434")

      result = boot(env:)

      expect(result.embedder).to be_a(SFL::LLM::Embedder)
    end

    it "raises Boot::Error when MISTRAL_API_KEY is missing for a mistral-provider task" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER" => "mistral",
        "SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "mistral-small-latest")

      expect { boot(env:) }.to raise_error(SFL::Boot::Error, /MISTRAL_API_KEY/)
    end

    it "does not require an API key for :ollama as a primary task provider, not just embedding" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER" => "ollama",
        "SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "llama3")

      expect { boot(env:) }.not_to raise_error
    end

    it "raises Boot::Error when a required provider API key is missing" do
      env = base_env.merge("SFL_TASK_CONTEXT_SYNTHESIS_PROVIDER" => "openai",
        "SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "gpt-x")
      # NOTE: no OPENAI_API_KEY set

      expect { boot(env:) }.to raise_error(SFL::Boot::Error, /OPENAI_API_KEY/)
    end

    it "does not require an API key for the ollama-provider embedding task" do
      expect { boot(env: base_env) }.not_to raise_error
    end

    it "returns nil llm_config/embedder/classifier when require_llm: false" do
      result = boot(env: base_env, require_llm: false)

      expect(result.llm_config).to be_nil
      expect(result.embedder).to be_nil
      expect(result.classifier).to be_nil
    end
  end

  describe "tracing" do
    let(:tracing_env) do
      base_env.merge(
        "LANGFUSE_PUBLIC_KEY" => "pk", "LANGFUSE_SECRET_KEY" => "sk", "LANGFUSE_HOST" => "http://example.invalid"
      )
    end

    it "does not call LangfuseReachability at all when no Langfuse keys are set" do
      allow(SFL::Boot::LangfuseReachability).to receive(:decide)

      boot(env: base_env, require_tracing: true)

      expect(SFL::Boot::LangfuseReachability).not_to have_received(:decide)
    end

    it "configures tracing when the endpoint is reachable" do
      allow(SFL::Boot::LangfuseReachability).to receive(:reachable?).and_return(true)
      allow(SFL::LLM::Tracing).to receive(:configure)

      boot(env: tracing_env, require_tracing: true)

      expect(SFL::LLM::Tracing).to have_received(:configure).with(
        host: "http://example.invalid",
        public_key: "pk",
        secret_key: "sk"
      )
    end

    it "skips tracing (without raising) when unreachable and non-interactive" do
      allow(SFL::Boot::LangfuseReachability).to receive(:reachable?).and_return(false)
      allow(SFL::LLM::Tracing).to receive(:configure)

      expect { boot(env: tracing_env, require_tracing: true, tty: false) }.to output.to_stderr

      expect(SFL::LLM::Tracing).not_to have_received(:configure)
    end

    it "raises Boot::Error when unreachable, interactive, and the operator declines" do
      allow(SFL::Boot::LangfuseReachability).to receive(:reachable?).and_return(false)

      expect do
        expect do
          boot(env: tracing_env, require_tracing: true, tty: true, input: StringIO.new("n\n"))
        end.to raise_error(SFL::Boot::Error, /Cancelled/)
      end.to output.to_stderr
    end

    it "does not run the reachability check at all when require_tracing: false" do
      allow(SFL::Boot::LangfuseReachability).to receive(:decide)

      boot(env: tracing_env, require_tracing: false)

      expect(SFL::Boot::LangfuseReachability).not_to have_received(:decide)
    end
  end

  describe "api_debug_errors (issue #3)" do
    it "defaults to false when SFL_API_DEBUG_ERRORS is unset" do
      result = boot(env: base_env)

      expect(result.api_debug_errors).to be false
    end

    it "is true only when SFL_API_DEBUG_ERRORS is exactly \"true\"" do
      expect(boot(env: base_env.merge("SFL_API_DEBUG_ERRORS" => "true")).api_debug_errors).to be true
      expect(boot(env: base_env.merge("SFL_API_DEBUG_ERRORS" => "1")).api_debug_errors).to be false
    end
  end

  describe "api_cors_origins (issue #35)" do
    it "defaults to an empty array when SFL_API_CORS_ORIGINS is unset" do
      result = boot(env: base_env)

      expect(result.api_cors_origins).to eq([])
    end

    it "splits SFL_API_CORS_ORIGINS on commas and trims surrounding whitespace" do
      result = boot(env: base_env.merge(
        "SFL_API_CORS_ORIGINS" => "https://webui.example.com, https://admin.example.com "
      ))

      expect(result.api_cors_origins).to eq(%w[https://webui.example.com https://admin.example.com])
    end
  end

  describe "Pass 1 sidecar command resolution" do
    it "returns a nil pass1_command when .sfl-python/interpreter_path has not been provisioned" do
      allow(File).to receive(:exist?).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return(false)

      result = boot(env: base_env)

      expect(result.pass1_command).to be_nil
      expect(result.pass1_env).to be_nil
      expect(result.spacy_model).to eq("en_core_web_sm")
    end

    it "builds [interpreter, sidecar_script, --model, model] when interpreter_path is provisioned" do
      allow(File).to receive(:exist?).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return(true)
      allow(File).to receive(:read).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return("/opt/py/bin/python3\n")

      result = boot(env: base_env.merge("SPACY_MODEL" => "en_core_web_lg"))

      expect(result.pass1_command).to eq(
        [
          "/opt/py/bin/python3",
          SFL::Core::PassOne::SpacySidecarParser::DEFAULT_SCRIPT_PATH,
          "--model",
          "en_core_web_lg",
]
      )
    end

    it "sets pass1_env to PYTHONPATH=PYTHON_TARGET_DIR when interpreter_path is provisioned (the vendored " \
      "install lives in an isolated --target dir, not the interpreter's own site-packages)" do
      allow(File).to receive(:exist?).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return(true)
      allow(File).to receive(:read).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return("/opt/py/bin/python3\n")

      result = boot(env: base_env)

      expect(result.pass1_env).to eq("PYTHONPATH" => SFL::Boot::PYTHON_TARGET_DIR)
    end
  end

  describe "ingest_classification and loader_drafting task configs" do
    it "defaults ingest_classification to the embedding task's default provider/model" do
      result = boot(env: base_env)

      task = result.llm_config.for(:ingest_classification)
      expect(task.provider).to eq(:ollama)
      expect(task.model).to eq("embeddinggemma-2:440m")
    end

    it "honors SFL_TASK_INGEST_CLASSIFICATION_MODEL/_PROVIDER overrides" do
      result = boot(env: base_env.merge(
        "SFL_TASK_INGEST_CLASSIFICATION_MODEL" => "custom-cheap-model",
        "SFL_TASK_INGEST_CLASSIFICATION_PROVIDER" => "openrouter"
      ))

      task = result.llm_config.for(:ingest_classification)
      expect(task.provider).to eq(:openrouter)
      expect(task.model).to eq("custom-cheap-model")
    end

    it "defaults loader_drafting to the same default provider/model as pass_two_annotation" do
      result = boot(env: base_env)

      pass_two = result.llm_config.for(:pass_two_annotation)
      loader_drafting = result.llm_config.for(:loader_drafting)
      expect(loader_drafting.provider).to eq(pass_two.provider)
      expect(loader_drafting.model).to eq(pass_two.model)
    end

    it "honors SFL_TASK_LOADER_DRAFTING_MODEL/_PROVIDER overrides" do
      result = boot(env: base_env.merge(
        "SFL_TASK_LOADER_DRAFTING_MODEL" => "custom-reasoning-model",
        "SFL_TASK_LOADER_DRAFTING_PROVIDER" => "anthropic",
        "ANTHROPIC_API_KEY" => "anthropic-key"
      ))

      task = result.llm_config.for(:loader_drafting)
      expect(task.provider).to eq(:anthropic)
      expect(task.model).to eq("custom-reasoning-model")
    end
  end

  describe "Result#classifier" do
    it "builds an LLM::Classifier wired to the ingest_classification task" do
      result = boot(env: base_env)

      expect(result.classifier).to be_a(SFL::LLM::Classifier)
    end
  end

  describe "database (require_db: true), against a real Postgres — see spec/support/store_test_db.rb" do
    it "returns a connected, extension-ready Sequel::Database" do
      env = base_env.merge("DATABASE_URL" => SFL::Store::StoreTestDb::TEST_DATABASE_URL)

      result = described_class.call(env:, load_dotenv: false, require_db: true, require_llm: false,
        require_tracing: false)

      begin
        expect(result.db).to be_a(Sequel::Database)
        expect(result.db.test_connection).to be true
      ensure
        result.db.disconnect
      end
    end

    it "raises Boot::Error when DATABASE_URL is unset" do
      env = base_env.except("DATABASE_URL")

      expect do
        described_class.call(env:, load_dotenv: false, require_db: true, require_llm: false, require_tracing: false)
      end.to raise_error(SFL::Boot::Error, /DATABASE_URL/)
    end

    it "resolves a task from its task_models row when no env var sets it (fact 58)" do
      env = base_env.merge("DATABASE_URL" => SFL::Store::StoreTestDb::TEST_DATABASE_URL)
      SFL::Store::StoreTestDb.clean!
      SFL::Store::PgModelRepository.new(SFL::Store::StoreTestDb.db)
        .assign(:loader_drafting, provider: "openrouter", model_id: "db/drafter")

      result = described_class.call(env:, load_dotenv: false, require_db: true, require_tracing: false)

      begin
        expect(result.llm_config.for(:loader_drafting)).to have_attributes(model: "db/drafter", source: :db)
        expect(result.llm_config.for(:pass_two_annotation)).to have_attributes(model: "openrouter/gemini-pro", source: :env)
        expect(result.llm_config.for(:context_synthesis).source).to eq(:default)
      ensure
        result.db.disconnect
      end
    end

    it "resolves task models from env and defaults only when require_db: false (fact 59)" do
      result = boot(env: base_env)

      expect(result.llm_config.tasks.values.map(&:source).uniq).to contain_exactly(:env, :default)
      expect(result.model_resolver.resolve[:loader_drafting].source).to eq(:default)
    end

    it "checks the schema after connecting only when require_schema: true" do
      env = base_env.merge("DATABASE_URL" => SFL::Store::StoreTestDb::TEST_DATABASE_URL)
      allow(described_class).to receive(:ensure_schema_current!).and_raise(SFL::Boot::Error, "behind")

      expect do
        described_class.call(env:, load_dotenv: false, require_db: true, require_llm: false, require_tracing: false, require_schema: true)
      end.to raise_error(SFL::Boot::Error, "behind")
      described_class.call(env:, load_dotenv: false, require_db: true, require_llm: false, require_tracing: false).db.disconnect
      boot(env: base_env, require_schema: true)
      expect(described_class).to have_received(:ensure_schema_current!).once
    end

    it "returns a nil db when require_db: false" do
      result = boot(env: base_env)

      expect(result.db).to be_nil
    end
  end

  describe ".ensure_schema_current!, against a real Postgres" do
    let(:latest) { Dir[File.join(described_class::MIGRATIONS_DIR, "*.rb")].map { |path| File.basename(path).to_i }.max }

    it "passes on the migrated test database" do
      expect { described_class.ensure_schema_current!(SFL::Store::StoreTestDb.db) }.not_to raise_error
    end

    it "names the database, its version and the latest version when the schema is behind" do
      schema = "sfl_unmigrated_#{Process.pid}"
      SFL::Store::StoreTestDb.db.run("CREATE SCHEMA #{schema}")
      db = SFL::Store::Database.connect(SFL::Store::StoreTestDb::TEST_DATABASE_URL.then { |url| "#{url}?search_path=#{schema}" })
      message = "database #{db.opts[:database]} is at schema version 0, latest is #{latest}; run `bundle exec rake db:migrate`"

      expect { described_class.ensure_schema_current!(db) }.to raise_error(SFL::Boot::SchemaError, message)
    ensure
      db&.disconnect
      SFL::Store::StoreTestDb.db.run("DROP SCHEMA IF EXISTS #{schema} CASCADE")
    end

    it "wraps a database failure in Boot::SchemaError" do
      db = SFL::Store::StoreTestDb.db
      allow(Sequel::Migrator).to receive(:is_current?).and_raise(Sequel::DatabaseError, "gone")

      expect { described_class.ensure_schema_current!(db) }.to raise_error(SFL::Boot::SchemaError, /schema check failed for database .*: gone/)
    end
  end

  describe ".model_catalogs" do
    it "lists the ruby_llm registry, Ollama at OLLAMA_BASE_URL and OpenRouter" do
      catalogs = described_class.model_catalogs(env: { "OLLAMA_BASE_URL" => "http://ollama:1" }, load_dotenv: false)

      expect(catalogs.map(&:name)).to eq(%w[ruby_llm ollama openrouter])
    end
  end

  # Fact 72: the values other code used to read from ENV itself.
  describe "settings read for other code" do
    it "resolves the embedding store's model from SFL_TASK_EMBEDDING_MODEL, else the store default" do
      expect(boot(env: base_env.merge("SFL_TASK_EMBEDDING_MODEL" => "nomic")).embedding_model).to eq("nomic")
      expect(boot(env: base_env, require_llm: false).embedding_model)
        .to eq(SFL::Store::PgEmbeddingStore::DEFAULT_MODEL)
    end

    it "ignores the legacy EMBEDDING_MODEL for the embedding store's model" do
      expect(boot(env: base_env.merge("EMBEDDING_MODEL" => "nomic"), require_llm: false).embedding_model)
        .to eq("embeddinggemma-2:440m")
    end

    it "defaults the store model to embeddinggemma-2:440m" do
      expect(SFL::Store::PgEmbeddingStore::DEFAULT_MODEL).to eq("embeddinggemma-2:440m")
    end

    it "returns DATABASE_URL, raising when it is unset" do
      expect(described_class.database_url(env: { "DATABASE_URL" => "postgres:///x" }, load_dotenv: false)).to eq("postgres:///x")
      expect { described_class.database_url(env: {}, load_dotenv: false) }.to raise_error(SFL::Boot::Error, /DATABASE_URL/)
    end

    it "opts into docker auto-start only with SFL_AUTO_START_DOCKER=1" do
      expect(described_class.auto_start_docker?(env: { "SFL_AUTO_START_DOCKER" => "1" })).to be(true)
      expect(described_class.auto_start_docker?(env: {})).to be(false)
    end

    it "skips the rack boot's LLM wiring only with SFL_SKIP_LLM_BOOT=true" do
      expect(described_class.skip_llm_boot?(env: { "SFL_SKIP_LLM_BOOT" => "true" })).to be(true)
      expect(described_class.skip_llm_boot?(env: { "SFL_SKIP_LLM_BOOT" => "1" })).to be(false)
      expect(described_class.skip_llm_boot?(env: {})).to be(false)
    end

    it "enables the rack boot's tracing only with SFL_ENABLE_TRACING=true" do
      expect(described_class.tracing_enabled?(env: { "SFL_ENABLE_TRACING" => "true" })).to be(true)
      expect(described_class.tracing_enabled?(env: { "SFL_ENABLE_TRACING" => "1" })).to be(false)
      expect(described_class.tracing_enabled?(env: {})).to be(false)
    end

    it "binds the API to HOST and PORT, defaulting to 0.0.0.0:3001" do
      expect(described_class.api_bind(env: {})).to eq(host: "0.0.0.0", port: "3001")
      expect(described_class.api_bind(env: { "HOST" => "localhost", "PORT" => "9" })).to eq(host: "localhost", port: "9")
    end
  end

  describe ".web_settings (the Roda app's Config)" do
    def web(env) = described_class.web_settings(env:, load_dotenv: false)

    let(:production) { { "RACK_ENV" => "production", "SESSION_SECRET" => "s3cret", "DATABASE_URL" => "postgres:///prod" } }

    it "passes SESSION_SECRET, RACK_ENV and DATABASE_URL through in production" do
      expect(web(production)).to eq(secret: "s3cret", environment: "production", db: { url: "postgres:///prod" })
    end

    it "raises in production when SESSION_SECRET or DATABASE_URL is unset" do
      expect { web(production.except("SESSION_SECRET")) }.to raise_error(SFL::Boot::Error, /SESSION_SECRET/)
      expect { web(production.except("DATABASE_URL")) }.to raise_error(SFL::Boot::Error, /DATABASE_URL/)
    end

    it "defaults to development with a random per-process secret and a local database" do
      settings = web({})

      expect(settings[:environment]).to eq("development")
      expect(settings[:secret]).to match(/\A\h{128}\z/)
      expect(web({})[:secret]).to eq(settings[:secret])
      expect(settings[:db][:url]).to eq("postgres://user:password@localhost:5432/app_development")
    end

    it "uses DATABASE_URL outside production when it is set" do
      expect(web("RACK_ENV" => "test", "DATABASE_URL" => "postgres:///t")[:db][:url]).to eq("postgres:///t")
    end

    it "loads .env only outside production" do
      allow(Dotenv).to receive(:load)

      described_class.web_settings(env: production, load_dotenv: true)
      expect(Dotenv).not_to have_received(:load)

      described_class.web_settings(env: {}, load_dotenv: true)
      expect(Dotenv).to have_received(:load)
    end

    it "reads RACK_ENV without .env, defaulting to development" do
      expect(described_class.rack_environment(env: {})).to eq("development")
      expect(described_class.rack_environment(env: { "RACK_ENV" => "production" })).to eq("production")
    end
  end

  describe "BERTopic sidecar and embedder settings" do
    let(:env_example) { File.read(File.expand_path("../../.env.example", __dir__)) }

    it "defaults the sidecar executable to python3 and runs the repo's sidecar script" do
      expect(boot(env: base_env).bertopic_command)
        .to eq(["python3", described_class::BERTOPIC_SIDECAR_SCRIPT])
    end

    it "resolves the sidecar script under sidecar/bertopic in the repo root" do
      expect(described_class::BERTOPIC_SIDECAR_SCRIPT).to end_with("sidecar/bertopic/bertopic_sidecar.py")
      expect(File.exist?(described_class::BERTOPIC_SIDECAR_SCRIPT)).to be(true)
    end

    it "takes the sidecar executable from SFL_BERTOPIC_PYTHON" do
      result = boot(env: base_env.merge("SFL_BERTOPIC_PYTHON" => "/opt/py/bin/python"))

      expect(result.bertopic_command).to eq(["/opt/py/bin/python", described_class::BERTOPIC_SIDECAR_SCRIPT])
    end

    it "treats a blank SFL_BERTOPIC_PYTHON as unset" do
      result = boot(env: base_env.merge("SFL_BERTOPIC_PYTHON" => "   "))

      expect(result.bertopic_command.first).to eq("python3")
    end

    it "splits SFL_BERTOPIC_SPEAKER_NAMES on commas and drops blank entries" do
      result = boot(env: base_env.merge("SFL_BERTOPIC_SPEAKER_NAMES" => "Alice, Bob,,"))

      expect(result.topic_speaker_names).to eq(%w[Alice Bob])
    end

    it "defaults topic_speaker_names to an empty array" do
      expect(boot(env: base_env).topic_speaker_names).to eq([])
    end

    it "names the embedding task's provider and endpoint in embedder_info" do
      expect(boot(env: base_env).embedder_info)
        .to include(provider: "ollama", endpoint: described_class::DEFAULT_OLLAMA_BASE_URL)
    end

    it "leaves embedder_info nil when require_llm: false" do
      expect(boot(env: base_env, require_llm: false).embedder_info).to be_nil
    end

    it "documents every BERTopic variable in .env.example" do
      expect(env_example).to include("SFL_BERTOPIC_PYTHON=python3", "SFL_BERTOPIC_SPEAKER_NAMES=")
    end
  end
end
