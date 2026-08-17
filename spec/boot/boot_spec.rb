# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"
require "stringio"

RSpec.describe SFL::Boot do
  let(:base_env) do
    {
      "DATABASE_URL" => "postgresql:///irrelevant-for-these-examples",
      "OPENROUTER_API_KEY" => "or-key",
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
    it "defaults pass_two_annotation and pass_two_batch_annotation to the same provider/model" do
      result = boot(env: base_env)

      pass_two = result.llm_config.for(:pass_two_annotation)
      pass_two_batch = result.llm_config.for(:pass_two_batch_annotation)

      expect(pass_two.provider).to eq(:openrouter)
      expect(pass_two.model).to eq("google/gemini-2.5-flash:free")
      expect(pass_two_batch.provider).to eq(:openrouter)
      expect(pass_two_batch.model).to eq("google/gemini-2.5-flash:free")
    end

    it "defaults context_synthesis to whatever pass_two_annotation resolved to" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_MODEL" => "openrouter/some-model",
        "SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER" => "openrouter")

      result = boot(env:)

      expect(result.llm_config.for(:context_synthesis).model).to eq("openrouter/some-model")
      expect(result.llm_config.for(:context_synthesis).provider).to eq(:openrouter)
    end

    it "lets SFL_TASK_CONTEXT_SYNTHESIS_* override the context_synthesis default" do
      env = base_env.merge("SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "openrouter/different-model",
        "ANTHROPIC_API_KEY" => "anthropic-key")

      result = boot(env:)

      expect(result.llm_config.for(:context_synthesis).model).to eq("openrouter/different-model")
    end

    it "defaults embedding to the ollama provider and EMBEDDING_MODEL (or embeddinggemma:latest)" do
      result = boot(env: base_env)

      embedding = result.llm_config.for(:embedding)
      expect(embedding.provider).to eq(:ollama)
      expect(embedding.model).to eq("embeddinggemma:latest")
    end

    it "prefers EMBEDDING_MODEL over the hardcoded embedding default" do
      env = base_env.merge("EMBEDDING_MODEL" => "some-other-model:latest")

      result = boot(env:)

      expect(result.llm_config.for(:embedding).model).to eq("some-other-model:latest")
    end

    it "prefers SFL_TASK_EMBEDDING_MODEL over EMBEDDING_MODEL" do
      env = base_env.merge("EMBEDDING_MODEL" => "legacy-var-model", "SFL_TASK_EMBEDDING_MODEL" => "new-var-model")

      result = boot(env:)

      expect(result.llm_config.for(:embedding).model).to eq("new-var-model")
    end

    it "applies SFL_TASK_<NAME>_TEMPERATURE as a params[:temperature]" do
      env = base_env.merge("SFL_TASK_PASS_TWO_ANNOTATION_TEMPERATURE" => "0.3")

      result = boot(env:)

      expect(result.llm_config.for(:pass_two_annotation).params).to eq(temperature: 0.3)
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
      allow(described_class).to receive(:require)

      boot(env: tracing_env, require_tracing: true)

      expect(described_class).to have_received(:require).with("dspy/o11y/langfuse")
    end

    it "skips tracing (without raising) when unreachable and non-interactive" do
      allow(SFL::Boot::LangfuseReachability).to receive(:reachable?).and_return(false)
      allow(described_class).to receive(:require)

      expect { boot(env: tracing_env, require_tracing: true, tty: false) }.to output.to_stderr

      expect(described_class).not_to have_received(:require).with("dspy/o11y/langfuse")
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
    it "defaults to API::Server::DEFAULT_CORS_ORIGINS when SFL_API_CORS_ORIGINS is unset" do
      result = boot(env: base_env)

      expect(result.api_cors_origins).to eq(SFL::API::Server::DEFAULT_CORS_ORIGINS)
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
      result = boot(env: base_env.merge("EMBEDDING_MODEL" => "embeddinggemma:latest"))

      task = result.llm_config.for(:ingest_classification)
      expect(task.provider).to eq(:ollama)
      expect(task.model).to eq("embeddinggemma:latest")
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

    it "returns a nil db when require_db: false" do
      result = boot(env: base_env)

      expect(result.db).to be_nil
    end
  end
end
