# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"
require "stringio"

RSpec.describe SFL::Boot do
  # rubocop:disable RSpec/VerifiedDoubles -- ruby_llm: is a duck-typed injectable seam
  # (#configure/#embed), not a stand-in for the real ::RubyLLM module — see
  # spec/llm/embedder_spec.rb for the same rationale.
  let(:ruby_llm_config) do
    double(
      "ruby_llm_config",
      "openrouter_api_key=": nil, "gemini_api_key=": nil, "openai_api_key=": nil, "anthropic_api_key=": nil,
      "ollama_api_base=": nil, "default_embedding_model=": nil
    )
  end
  let(:ruby_llm) { double("ruby_llm") }
  let(:base_env) do
    {
      "DATABASE_URL" => "postgresql:///irrelevant-for-these-examples",
      "OPENROUTER_API_KEY" => "or-key",
    }
  end
  # rubocop:enable RSpec/VerifiedDoubles

  before { allow(ruby_llm).to receive(:configure).and_yield(ruby_llm_config) }

  # Every example here passes require_db: false, load_dotenv: false, require_tracing: false
  # unless a spec is specifically exercising that concern — this is the unit-level slice the
  # task calls for ("ENV-parsing/Config-building logic ... unit-tested without touching
  # Postgres"); DB connection itself is covered separately below against a real Postgres, the
  # same opt-in pattern spec/support/store_test_db.rb already establishes for spec/store.
  def boot(env:, **overrides)
    described_class.call(
      env:, load_dotenv: false, require_db: false, require_tracing: false, ruby_llm:,
      **overrides
    )
  end

  describe "ENV loading" do
    it "loads .env via Dotenv when load_dotenv: true" do
      allow(Dotenv).to receive(:load)

      described_class.call(env: base_env, load_dotenv: true, require_db: false, require_tracing: false, ruby_llm:)

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
      expect(pass_two.model).to eq("mistralai/mistral-small-3.2-24b-instruct")
      expect(pass_two_batch.provider).to eq(:openrouter)
      expect(pass_two_batch.model).to eq("mistralai/mistral-small-3.2-24b-instruct")
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

    it "builds a ready-to-use ChatFactory from the resolved config" do
      result = boot(env: base_env)

      expect(result.chat_factory).to be_a(SFL::LLM::ChatFactory)
    end

    it "builds a real Embedder wired to OLLAMA_BASE_URL/the resolved embedding model" do
      env = base_env.merge("OLLAMA_BASE_URL" => "http://tinybot:11434")

      result = boot(env:)

      expect(result.embedder).to be_a(SFL::LLM::Embedder)
      expect(ruby_llm_config).to have_received(:ollama_api_base=).with("http://tinybot:11434/v1")
    end

    it "sets the RubyLLM provider API key for every distinct provider actually in use" do
      env = base_env.merge("SFL_TASK_CONTEXT_SYNTHESIS_PROVIDER" => "anthropic",
        "SFL_TASK_CONTEXT_SYNTHESIS_MODEL" => "claude-x", "ANTHROPIC_API_KEY" => "anthropic-key")

      boot(env:)

      expect(ruby_llm_config).to have_received(:openrouter_api_key=).with("or-key")
      expect(ruby_llm_config).to have_received(:anthropic_api_key=).with("anthropic-key")
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

    it "returns nil llm_config/chat_factory/embedder when require_llm: false" do
      result = boot(env: base_env, require_llm: false)

      expect(result.llm_config).to be_nil
      expect(result.chat_factory).to be_nil
      expect(result.embedder).to be_nil
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
        host: "http://example.invalid", public_key: "pk", secret_key: "sk"
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

  describe "Pass 1 sidecar command resolution" do
    it "returns a nil pass1_command when .sfl-python/interpreter_path has not been provisioned" do
      allow(File).to receive(:exist?).with(SFL::Boot::INTERPRETER_PATH_FILE).and_return(false)

      result = boot(env: base_env)

      expect(result.pass1_command).to be_nil
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
